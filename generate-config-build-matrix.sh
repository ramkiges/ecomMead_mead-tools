#!/bin/sh
# generates https://confluence.wsgc.com/display/ES/MFE+Config+Build+Status
PATH=/apps/mead-tools:/usr/local/bin:/apps:/bin:/usr/bin:/sbin:/usr/sbin:/apps/scripts/env_summary
export PATH

base=$(dirname $0)
[[ -e ${base}/generate-mfe.env ]] && . ${base}/generate-mfe.env || .  /apps/scripts/env_summary/generate-mfe.env

TMP=$(mktemp -d -t tmp.$(basename $0).XXX)
find /tmp -maxdepth 1 -mindepth 1 -name "mfe-build-result-*" -mmin +200 -amin +200 -exec rm -rf {} \; 2>/dev/null &

OUTFILE=$TMP/mfe-build-result.html
PAGENAME="MFE Config Build Status"

COLOR_GOOD="#e6ffe6"
COLOR_FAIL="#ffb3b3"
COLOR_NULL="#e1e1ea"

echo "/// $(basename $0) $(date +'%Y-%m-%d %H:%M') ///"

[[ -z $TMP ]] && BailOut "Why is TMP empty?"
time git clone -q $REPO $TMP/repo || BailOut "Unable to clone $REPO"
cd $TMP/repo || BailOut "Unable to cd to $TMP/repo"
git pull -q >/dev/null 2>&1

cleanUp() {
  { set +x; } 2>/dev/null
  [[ -n $TMP ]] && rm -rf $TMP
}
trap cleanUp EXIT

[[ -n $1 ]] && ENV_LIST=$* || ENV_LIST="$(get-env-list -e bpv) $(get-env-list -e uat) $(get-env-list -e rgs) $(get-env-list -e qa) $(get-env-list -e int) $(get-env-list -e perf)"
STATS=$TMP/repo/data/$(basename $BUILD_STATS)

TOTAL_NULL=0
TOTAL_GOOD=0
TOTAL_FAIL=0
TOTAL_ENV=0

first=$(awk -F, '{ print $2 }' $STATS | grep "^[0-9].*" | sort -u | head -1)
first="${first:0:4}-${first:4:2}-${first:6:2} ${first:8:2}:${first:10:2}"
last=$(awk -F, '{ print $2 }' $STATS | grep "^[0-9].*" | sort -u | tail -1)
last="${last:0:4}-${last:4:2}-${last:6:2} ${last:8:2}:${last:10:2}"

rm -f $OUTFILE
HTML "$HEADER"

HTML "<p>Date range: <i>$first</i> - <i>$last</i></p>"

HTML "<table border='1' width='35%'>"
HTML "<tr>"
HTML "  <th style='text-align:center'>Success</th>"
HTML "  <td style='text-align:center'>@TOTAL_GOOD@ (@SPCT@%)</td>"
HTML "  <td bgcolor='$COLOR_GOOD' style='text-align:center'><font size='-1'><i>[Node]</i></font></td>"
HTML "</tr>"

HTML "<tr>"
HTML "  <th style='text-align:center'>Failure</th>"
HTML "  <td style='text-align:center'>@TOTAL_FAIL@</td>"
HTML "  <td bgcolor='$COLOR_FAIL' style='text-align:center'>"
HTML "  <font size='-1'><i>[Node] Success%</i></font>"
HTML "  <br><font size='-2'><i>[Cause of failure]</i></font></br>"
HTML "  <br><font size='-2'><i>[Date of last good build]</i></font></br>"
HTML "  <br><font size='-2'>[cpu%] [mem%] [elapsed time]</font></br>"
HTML "  </td>"
HTML "</tr>"

#HTML "<tr>"
#HTML "  <th style='text-align:center'>N/A</th>"
#HTML "  <td style='text-align:center'>@TOTAL_NULL@</td>"
#HTML "  <td bgcolor='$COLOR_NULL' style='text-align:center'><font size='-1'>&nbsp;</font></td>"
#HTML "</tr>"
HTML "</table>"

HTML "<table border='1' width='90%'>"
HTML "<tr>"
HTML "<th>&nbsp;</th>"
for b in $(get-brand-list | tr '[:lower:]' '[:upper:]')
do
  HTML "<th style='text-align:center'>$b</th>"
done
HTML "</tr>"

for env in $ENV_LIST
do
  [[ $env =~ prod ]] && continue
  link="<a href='https://ecombuild.wsgc.com/jenkins/job/config-$env-mfe/'>$env</a>"

  HTML "<tr>"
  HTML "<td>$link</td>"
  for b in $(get-brand-list | tr '[:lower:]' '[:upper:]')
  do
    TOTAL_ENV=$(expr $TOTAL_ENV + 1)
    COLOR=
    DATE=

    # grab the most recent single-brand build for this brand
    sd=$(grep "^$env,.*,$b," $STATS | sort -u -t, -k1,2 | tail -1 | awk -F, '{ print $2 }')

    # grab the most recent multi-brand build for this brand
    md=$(grep "^$env,.*$b" $STATS | sort -u -t, -k1,2 | tail -1 | awk -F, '{ print $2 }')

    # if the single build is newer, use that; otherwise use the multi-build
    [[ $sd -ge $md ]] && date=$sd || date=$md

    # using that date as the key, grab the most recent build
#set -x
    build=$(grep "^$env,$date.*$b" $STATS | sort -u -t, -k1,2 | tail -1 | awk -F, '{ print $3 }')
    # using the build as the key, grab the rest of the info
    result=$(grep "^$env,$date,$build" $STATS | sort -u -t, -k1,2 | tail -1 | awk -F, '{ print $5 }' | awk '{ print $1 }')
    node=$(grep "^$env,$date,$build" $STATS | sort -u -t, -k1,2 | tail -1 | awk -F, '{ print $4 }' | awk '{ print $1 }' | sed -es/ecom-jenkins-agent-//g)
    job=$(grep "^$env,$date,$build" $STATS | sort -u -t, -k1,2 | tail -1 | awk -F, '{ print $10 }')
    reason=$(grep "^$env,$date,$build" $STATS | sort -u -t, -k1,2 | tail -1 | awk -F, '{ print $11 }')
    #[[ $result =~ abort ]] && continue
    cpu=$(grep "^$env,$date,$build" $STATS | sort -u -t, -k1,2 | tail -1 | awk -F, '{ print $13 }')
    mem=$(grep "^$env,$date,$build" $STATS | sort -u -t, -k1,2 | tail -1 | awk -F, '{ print $14 }')
    elt=$(grep "^$env,$date,$build" $STATS | sort -u -t, -k1,2 | tail -1 | awk -F, '{ print $15 }')
#{ set +x; } 2>/dev/null
    [[ -n $job ]] && job="https://ecombuild.wsgc.com/jenkins/job/$job"
    [[ -n $job && -n $build ]] && job="$job/$build/console"
    sample=$(grep "^$env,$date," $STATS | sort -u -t, -k1,2 | tail -1 | awk -F, '{ print $2 }')
    sample="${sample:0:4}-${sample:4:2}-${sample:6:2} ${sample:8:2}:${sample:10:2}"

    #echo "$env $b $date $result $reason $build $job"

    if [[ -z $result ]]
    then 
      TOTAL_NULL=$(expr $TOTAL_NULL + 1)
      COLOR=$COLOR_NULL 
    fi

    if [[ $result =~ fail || $reason =~ abort ]]
    then 
      result=
      TOTAL_FAIL=$(expr $TOTAL_FAIL + 1)
      COLOR=$COLOR_FAIL
      DATE=$(grep "^$env,.*,success,.*$b" $STATS | sort -u | tail -1 | awk -F, '{ print $2 }')
      [[ -n $DATE ]] && DATE="${DATE:0:4}-${DATE:4:2}-${DATE:6:2}" 
      [[ -z $DATE && -z $reason ]] && result="<br>$DATE</br>" 
      [[ -n $DATE && -n $reason ]] && result="<br>$reason</br><br>$DATE</br>" 
      [[ -z $DATE && -n $reason ]] && result="<br>$reason</br>" 
    fi

    if [[ $result =~ succ ]]
    then
      result=
      TOTAL_GOOD=$(expr $TOTAL_GOOD + 1)
      COLOR=$COLOR_GOOD
    fi

    # figure out the stats for a single brand/env
    b_cnt=$(grep "^$env,.*$b" $STATS | sort -u | wc -l)
    if [[ $b_cnt -gt 0 ]]
    then
      b_suc=$(grep "^$env,.*,success,.*$b" $STATS | sort -u | wc -l)
      b_pct=$(bc <<< "scale=4; $b_suc/$b_cnt * 100")
      b_pct=$(printf "%.0f%%" $b_pct)
    else
      b_pct=
    fi

    [[ -n $job ]] && node="<a href='$job' title='$sample'>$node</a>"
    HTML "  <td bgcolor='$COLOR' style='text-align:center'>"
    HTML "    <font size='-1'>$node</font>"
    HTML "    <font size='-2'><i>$b_pct</i></font>"
    HTML "    <font size='-2'><i>$result</i></font>"
    [[ -n $mem || -n $cpu ]] && HTML "    <font size='-3'><br>${cpu}% ${mem}% ${elt}</br></font>"
    HTML "  </td>"
  done
  HTML "</tr>"
done
HTML "</table>"

T=$(expr $TOTAL_GOOD + $TOTAL_FAIL)
FPCT=$(bc <<< "scale=4; $TOTAL_FAIL/$T * 100")
FPCT=$(printf "%.2f" "$FPCT")
SPCT=$(bc <<< "scale=4; $TOTAL_GOOD/$T * 100")
SPCT=$(printf "%.2f" "$SPCT")
sed -i $OUTFILE \
  -es/"@TOTAL_NULL@"/$TOTAL_NULL/g \
  -es/"@TOTAL_GOOD@"/$TOTAL_GOOD/g \
  -es/"@TOTAL_FAIL@"/$TOTAL_FAIL/g \
  -es/"@TOTAL_ENV@"/$TOTAL_ENV/g \
  -es/"@FPCT@"/$FPCT/g \
  -es/"@SPCT@"/$SPCT/g 

# timing
#HTML "<h3>Average Build Durations - Previous $SPAN</h3>"
HTML "<h3>${PCTL}th Percentile Build Durations - Previous $SPAN</h3>"
HTML "<p>"
HTML "<font size='-1' color='$TEXT_SUCC'><i>Successful build</i></font><br/>"
HTML "<font size='-1' color='$TEXT_FAIL'><i>Failed build</i></font>"
HTML "</p>"

BRAND_LIST=$(awk -F, '{ print $7 }' $STATS | grep "^[A-Z][A-Z]$" | sort -u)
ENV_LIST=$(awk -F, '{ print $1 }' $STATS | egrep -iv "Environ" | sort -u)
HTML "<table border='1' width='55%'>"

HTML "<tr>"
HTML "<th style='text-align:center'><font size='-1'>Environment</font></th>"
for brand in $BRAND_LIST
do
  HTML "<th style='text-align:center'><font size='-1'>$brand</font></th>"
done
HTML "<th style='text-align:center'><font size='-1'>All Brands</font></th>"
HTML "</tr>"

for enviro in $ENV_LIST
do
  E_PCTL_S=$(mktemp -p /tmp tmp.stats-succ.XXX) 
  E_PCTL_F=$(mktemp -p /tmp tmp.stats-fail.XXX) 
  e_ps=0; e_pf=0; e_as=; e_af=; e_cs=0; e_cf=0; e_ts=0; e_tf=0

  HTML "<tr>"
  HTML "  <td><font size='-1'>$enviro</font></td>"
  for brand in $BRAND_LIST
  do
    B_PCTL_S=$(mktemp -p /tmp tmp.stats-succ.XXX) 
    HTML "<td style='text-align:right'>"
    p_s=0; t_s=0; a_s=; c_s=$(egrep "^$enviro,.*,succ.*,$brand," $STATS | awk -F, '{ print $6 }' | wc -l)
    e_cs=$(expr $e_cs + $c_s)
    for x in $(egrep "^$enviro,.*,succ.*,$brand," $STATS | awk -F, '{ print $6 }')
    do
      t_s=$(expr $t_s + $(expr $x / 1000))
      echo "$t_s" >> $B_PCTL_S
      echo "$t_s" >> $E_PCTL_S
    done # data row
    e_ts=$(expr $e_ts + $t_s)
    [[ $c_s -gt 0 ]] && a_s=$(expr $t_s / $c_s)
    [[ -n $a_s ]] && a_s=$(date -u -d @${a_s} +"%T")

    [[ $c_s -gt 0 ]] && p_s=$(datamash -t, perc:$PCTL 1 < $B_PCTL_S)
    [[ -n $p_s ]] && p_s=$(date -u -d @${p_s} +"%T")
    [[ $p_s = "00:00:00" ]] && p_s=
    #echo "pctl-s: $enviro $brand: $p_s samples: $(wc -l $B_PCTL_S | awk '{ print $1 }')"

    #HTML "<font size='-1' color='$TEXT_SUCC'>$a_s ($p_s)</font>"
    HTML "<font size='-1' color='$TEXT_SUCC'>$p_s</font>"
    HTML "<br>"

    B_PCTL_F=$(mktemp -p /tmp tmp.stats-fail.XXX) 
    p_f=0; t_f=0; a_f=; c_f=$(egrep "^$enviro,.*,fail.*,$brand," $STATS | awk -F, '{ print $6 }' | wc -l)
    e_cf=$(expr $e_cf + $c_f)
    for x in $(egrep "^$enviro,.*,fail.*,$brand," $STATS | awk -F, '{ print $6 }')
    do
      t_f=$(expr $t_f + $(expr $x / 1000))
      echo "$t_f" >> $B_PCTL_F
      echo "$t_f" >> $E_PCTL_F
    done # data row
    e_tf=$(expr $e_ts + $t_s)
    [[ $c_f -gt 0 ]] && a_f=$(expr $t_f / $c_f)
    [[ -n $a_f ]] && a_f=$(date -u -d @${a_f} +"%T")

    [[ $c_f -gt 0 ]] && p_f=$(datamash -t, perc:$PCTL 1 < $B_PCTL_F)
    [[ -n $p_f ]] && p_f=$(date -u -d @${p_f} +"%T")
    [[ $p_f = "00:00:00" ]] && p_f=
    #echo "pctl-f: $enviro $brand: $p_f samples: $(wc -l $B_PCTL_F | awk '{ print $1 }')"

    #HTML "<font size='-1' color='$TEXT_FAIL'>$a_f ($p_f)</font>"
    HTML "<font size='-1' color='$TEXT_FAIL'>$p_f</font>"
    HTML "</br>"
    HTML "</td>"

    rm -f $B_PCTL_S $B_PCTL_F
  done # brand

  [[ $e_cs -gt 0 ]] && e_as=$(expr $e_ts / $e_cs)
  [[ -n $e_as ]] && e_as=$(date -u -d @${e_as} +"%T")

  [[ $e_cf -gt 0 ]] && e_af=$(expr $e_tf / $e_cf)
  [[ -n $e_af ]] && e_af=$(date -u -d @${e_af} +"%T")

  #set -x
  e_ps=$(datamash -t, perc:$PCTL 1 < $E_PCTL_S)
  [[ -n $e_ps ]] && e_ps=$(date -u -d @${e_ps} +"%T")
  #{ set +x; } 2>/dev/null
  [[ $e_ps = "00:00:00" ]] && e_ps=

  #set -x
  e_pf=$(datamash -t, perc:$PCTL 1 < $E_PCTL_F)
  [[ -n $e_pf ]] && e_pf=$(date -u -d @${e_pf} +"%T")
  #{ set +x; } 2>/dev/null
  [[ $e_pf = "00:00:00" ]] && e_pf=

  HTML "<td style='text-align:right'>"
  #HTML "<font size='-1' color='$TEXT_SUCC'>$e_as</font>"
  HTML "<font size='-1' color='$TEXT_SUCC'>$e_ps</font>"
  HTML "<br>"
  #HTML "<font size='-1' color='$TEXT_FAIL'>$e_af</font>"
  HTML "<font size='-1' color='$TEXT_FAIL'>$e_pf</font>"
  HTML "</br>"
  HTML "</td>"
  HTML "</tr>"

  rm -f $E_PCTL_S $E_PCTL_F
done # enviro
HTML "</table>"

# agent stats
AGENT_LIST=$(grep "ecom-jenkins-agent" $STATS | awk -F, '{ print $4 }' | sort -u)
AGENT_COUNT=$(echo "$AGENT_LIST" | wc -l)
BUILD_COUNT=$(grep "ecom-jenkins-agent" $STATS | wc -l)

t_succ=0
t_fail=0
t_total=0

HTML "<h3>Build Agent Statistics</h3>"
HTML "<table border='1' width='40%'>"
HTML "<tr>" 
HTML "  <th style='text-align:center'><font size='-1'>Agent</font></th>"
HTML "  <th style='text-align:center'><font size='-1'>Success</font></th>"
HTML "  <th style='text-align:center'><font size='-1'>Failure</font></th>"
HTML "  <th style='text-align:center'><font size='-1'>Success<br>Rate</br></font></th>"
HTML "  <th style='text-align:center'><font size='-1'>Load<br>Share</br></font></th>"
HTML "</tr>" 

for agent in $AGENT_LIST
do
  label=$(sed -es/ecom-jenkins-agent-//g <<< $agent)
  total=$(grep ",$agent," $STATS | wc -l)
  succ=$(grep ",$agent,succ" $STATS | wc -l)
  #fail=$(egrep ",$agent,fail|,$agent,abort" $STATS | wc -l)
  fail=$(egrep ",$agent,fail" $STATS | wc -l)
  spct=$(bc <<< "scale=4; $succ/$total * 100")
  spct=$(printf "%.2f" "$spct")

  t_succ=$(expr $t_succ + $succ)
  t_fail=$(expr $t_fail + $fail)
  t_total=$(expr $t_total + $t_succ + $t_fail)
  share=$(bc <<< "scale=4; $(expr $succ + $fail)/$BUILD_COUNT * 100")
  share=$(printf "%.2f" "$share")

  HTML "<tr>" 
  HTML "  <td style='text-align:center'><a href='https://ecombuild.wsgc.com/jenkins/computer/ecom-jenkins-agent-$label/'><font size='-1'>${label}</font></a></td>"
  HTML "  <td style='text-align:right'><font size='-1'>${succ}</font></td>"
  HTML "  <td style='text-align:right'><font size='-1'>${fail}</font></td>"
  HTML "  <td style='text-align:right'><font size='-1'>${spct}%</font></td>"
  HTML "  <td style='text-align:right'><font size='-1'>${share}%</font></td>"
  HTML "</tr>"
done

#tpct=$(bc <<< "scale=4; $t_succ/$t_total * 100")
#tpct=$(printf "%.2f" "$tpct")
#HTML "<tr>"
#HTML "<th>$AGENT_COUNT</th>"
#HTML "<th>$t_succ</th>"
#HTML "<th>$t_fail</th>"
#HTML "<th>$t_pct</th>"
#HTML "</tr>"

HTML "</table>"

# failure reasons
FAIL=$(mktemp -p /tmp tmp.failure-reasons.XXX)
grep -i ",failure," $STATS | awk -F, '{ print $11 }' | sort -u --ignore-case | egrep -iv "^$" |
while read reason
do
  count=$(grep -i ",failure,.*,$reason" $STATS | wc -l | awk '{ print $1 }')
  #echo "reason: $reason=$count"
  echo "$count,$reason" >> $FAIL
done

[[ $DAYS -gt 1 ]] && SPAN="$DAYS Days" || SPAN="24 Hours"
HTML "<h3>MFE Build Failure Statistics - Previous $SPAN</h3>"
HTML "<table border='1' width='45%'>"
HTML "<tr>"
HTML "  <th style='text-align:center'><font size='-1'>Reason</font></th>"
HTML "  <th style='text-align:center'><font size='-1'>Count</font></th>"
HTML "</tr>"

sort -rn $FAIL | awk -F, '{ print $1, $2 }' |
while read count reason
do
  HTML "<tr>"
  HTML "  <td><font size='-1'>$reason</font></td><td><font size='-1'>$count</font></td>"
  HTML "</tr>"
done
HTML "</table>"
HTML "<font size='-2'>Generated on $(hostname)</font>"
rm $FAIL 

{ set +x; } 2>/dev/null
echo "*** Update confluence $PAGENAME $OUTFILE"
sh $CCLIDIR/confluence.sh --space "$DOC_SPACE" --title "$PAGENAME" --action storepage --file $OUTFILE --noConvert --verbose || BailOut "Confluence update failed"

[[ $LOGNAME = "jenkins" ]] && cp $TMP/repo/$(basename $0) /apps/scripts/env_summary >/dev/null 2>&1

exit 0
