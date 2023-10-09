#!/bin/bash
PATH=/apps/mead-tools:/usr/local/bin:/bin:/usr/bin:/sbin:/usr/sbin:/apps/scripts/env_summary:$HOME/bin:$PATH
P_JSON=/usr/lib/node_modules/@mfe-build/mfe-build/package.json
[[ -z $BUILD ]] && BUILD=false
[[ -z $DEPTH ]] && DEPTH=10

cleanUp() {
{ set +x; } 2>/dev/null
  [[ -n $TMP ]] && rm -rf $TMP
}
trap cleanUp EXIT

base=$(dirname $0)
[[ -e ${base}/generate-mfe.env ]] && . ${base}/generate-mfe.env || . /apps/scripts/env_summary/generate-mfe.env

[[ -n $1 ]] && ENV_LIST=$* || ENV_LIST=$(get-env-list)

export TMP=$(mktemp -d -t tmp.$(basename $0).XXX )
time git clone -q --depth 1 $REPO $TMP/repo || BailOut "Unable to clone mfe-data repo $REPO"
cd $TMP/repo || BailOut "Unable to cd to $TMP/repo"
BRANCH=$(git branch | awk '{ print $NF }')

export BUILD_STATS=$TMP/repo/data/mfe-build-stats.csv
[[ -e $BUILD_STATS ]] || exit 1
#echo "DAYS: $DAYS"
echo "DEPTH: $DEPTH"

for env in $ENV_LIST
do
  #[[ $BUILD =~ true ]] && jenkins-jnlp build -s config-$env-mfe -p FORCE_RUN=true 

  #for job in $(jenkins-jnlp list-jobs | grep "config-$env.*-mfe")
  for job in $(jenkins-jnlp list-jobs | egrep "config-$env-mfe|config-$env[a-z][a-z]-mfe")
  do
    url="https://ecombuild.wsgc.com/jenkins/job/$job"
    id=$(curl -sqk $url/lastBuild/api/json?tree=id | jq -r .id 2>/dev/null | tr "[:upper:]" "[:lower:]")
    e=$(expr $id - $DEPTH)

    if [[ $FORCE =~ true ]]
    then
      egrep -vi "^$env," $BUILD_STATS > $BUILD_STATS.new
      mv $BUILD_STATS.new $BUILD_STATS
    fi

    for id in $(eval echo {$id..$(expr $id - $DEPTH + 1)})
    do
      reason=","

      # skip this id if we already have this build
      xst=$(grep "^$env,.*,$id," $BUILD_STATS)
      [[ -n $xst && -z $FORCE ]] && continue

      console="$url/$id/consoleText"
      result=$(curl -sqk $url/$id/api/json?tree=result | jq -r .result 2>/dev/null | tr "[:upper:]" "[:lower:]")
      [[ $result =~ null ]] && continue
      [[ $result =~ unstable ]] && continue
      [[ $result =~ fail ]] && reason="unspecified,"
      [[ $result =~ aborted ]] && continue

      duration=$(curl -sqk $url/$id/api/json?tree=duration | jq -r .duration 2>/dev/null | tr "[:upper:]" "[:lower:]")
      [[ -z $duration ]] && continue
      [[ $duration -lt 999 ]] && continue

      node=$(curl -sqk $url/$id/api/json?tree=builtOn | jq -r .builtOn 2>/dev/null | tr "[:upper:]" "[:lower:]")
      [[ -z $node ]] && continue

      ts=$(curl -sqk $url/$id/api/json?tree=timestamp | jq -r .timestamp 2>/dev/null | tr "[:upper:]" "[:lower:]")
      ts=${ts:0:10}
      ts=$(date -d@${ts} +'%Y%m%d%H%M%S' 2>/dev/null)
      [[ $ts -lt $OLD ]] && break

      cl=$(curl -sqk $url/$id/api/xml | xmlstarlet sel -t -v "freeStyleBuild/action/parameter[name='CONCEPT_LIST']" | sed -es/CONCEPT_LIST//gi | sed -es/','/' '/g | tr '[:lower:]' '[:upper:]')
      fl=$(curl -sqk $url/$id/api/xml | xmlstarlet sel -t -v "freeStyleBuild/action/parameter[name='MFE_FEATURE_LIST']" | sed -es/MFE_FEATURE_LIST//gi | sed -es/','/' '/g)

      # get build tool version
      [[ $LOGNAME =~ jenkins ]] || bv=$(ssh -q -tt $node "jq ._requested.raw $P_JSON | sed -es/\\\"//g | awk -F\@ '{ print \$NF }'" | dos2unix -q | egrep -iv "null")

      out=$(mktemp -p /tmp tmp.mfe-build-history.XXX)
      curl -fsqk $console > $out

      # get reason for failure
      if [[ $result =~ fail || $reason =~ abort ]]
      then
        # grab the feature being built, so we know which one errored out
        feature=$(grep -i "Installing dependencies for" $out | grep -iv "error" | tail -1 | awk '{ print $NF }')

        egrep -iq "error from server.*etcd" $out && reason="etcd down,enviro"
        egrep -iq "EtcdFailureException" $out && reason="etcd failure,tooling"
        egrep -iq "503.*Unavailable" $out && reason="etcd 503,tooling"
        egrep -iq "syncappconfig-job-chart.*context deadline exceeded" $out && reason="etcd timeout,enviro"
        egrep -iq "etcdserver.*apply request took too long" $out && reason="etcd timeout,enviro"

        egrep -iq "ArtifactCreationException" $out && reason="artifact Creation Exception,"
        egrep -iq "git clone failed" $out && reason="git clone failed,enviro"
        egrep -iq "Error: Cannot find module" $out && reason="cannot find module,code"
        egrep -iq "Error: UPGRADE FAILED" $out && reason="helm error(?),"
        egrep -iq "Cannot find a definition" $out && reason="can't find application definition,code"
        egrep -iq "ERROR: Cannot resolve feature" $out && reason="can't resolve feature,code"
        egrep -iq "etcd-syncappconfig.*fail:" $out && reason="syncappconfig failure,tooling"
        egrep -iq "Error: No configuration files found" $out && reason="missing config files,code"
        egrep -iq "json are in sync" $out && reason="package/package-lock out of sync,code"
        egrep -iq "SyntaxError" $out && reason="syntax error,code"

        egrep -iq "npm ERR!.*not accessible from" $out && reason="package not accessible,code"
        egrep -iq "npm ERR! code E404" $out && reason="unable to download artifact,enviro"
        egrep -iq "npm ERR! Cannot read property.*of undefined" $out && reason="can't read undefined property,code"
        egrep -iq "npm ERR! Invalid Version" $out && reason="invalid version,code"
        egrep -iq "npm ERR!.*does not satisfy" $out && reason="unsatisfied dependency,code"
        egrep -iq "npm ERR! This is an error with npm itself" $out && reason="npm error"
        egrep -iq "snapshot.*failed" $out && reason="snapshotrepo down,enviro"
        egrep -iq "Unexpected end of JSON input" $out && reason="truncated file,enviro"
        egrep -iq "Unexpected warning for.*snapshot" $out && reason="snapshotrepo down,enviro"
        egrep -iq "Unexpected warning for.*snapshot.*socket hang up" $out && reason="snapshotrepo socket hang up,enviro"
        egrep -iq "ETCD is null" $out && reason="tooling issue (get-etcd-env),tooling"
        egrep -iq "No space left on device" $out && reason="disk full,enviro"
        egrep -iq "Not enough free space in" $out && reason="not enough free space to start,enviro"
        egrep -iq "java.lang.OutOfMemoryError" $out && reason="out of memory,enviro"
        egrep -iq "syncappconfig-job-chart.*error" $out && reason="syncapp failure,"
        egrep -iq "fork: retry: No child processes" $out && reason="out of processes,enviro"
        egrep -iq "Cannot run program" $out && reason="out of processes,enviro"
        egrep -iq "fatal error: newosproc" $out && reason="out of processes,enviro"
        egrep -iq "failed to create new OS thread" $out && reason="out of processes,enviro"
        egrep -iq "Unable to download.*mfe-interim-build-tool" $out && reason="can't download build-tool,enviro"
        egrep -iq "Error: failed to download helm-custom" $out && reason="failed to download helm chart,enviro"
        egrep -iq "Remote call on.*failed" $out && reason="jenkins node problem (terminated),enviro"
        egrep -iq "ERROR: ecom-jenkins-agent.*is offline" $out && reason="jenkins node problem (offline),enviro"
        egrep -iq "Terminated.*/apps/mead-tools/mfe-config-template" $out && reason="jenkins job timeout,enviro"
        egrep -iq "Build timed out" $out && reason="jenkins job timeout,enviro"
        egrep -iq "!!!buildtool failed=" $out && reason="buildtool failed,code"
        egrep -iq "SELF_SIGNED_CERT_IN_CHAIN" $out && reason="snapshotrepo certificate,enviro"
        egrep -iq "Network closed for unknown reason" $out && reason="network error,enviro"
        egrep -iq "'Execute shell' marked build as failure" $out && reason="shell failure(?),enviro"

        # more specific errors - the order is important
        err=$(egrep -i "InternalServerError:" $out | tail -1 )
        [[ -n $err ]] && reason="buildtool error,tooling"

        rpo=$(egrep -i "Unable to clone" $out | tail -1 | awk '{ print $NF }')
        [[ -n $rpo ]] && reason="can't clone ($rpo),config"

        bch=$(egrep -i "fatal: Remote branch.*not found" $out | tail -1 | awk '{ print $4 }')
        [[ -n $bch ]] && reason="missing branch ($bch),config"

        egrep -iq "concept builds complete" $out && feature="All builds complete"
        egrep -iq "error installing dependencies" $out && reason="error installing dependencies ($feature),enviro"

        err=$(egrep -i "Error: Error:" $out | egrep -iv 'Command failed' | tail -1 | sed -es/"Error: Error: "//g | sed "s/^[ \t]*//" | sed -es/\\.//g)
        [[ -n $err ]] && reason="build error ($err),code"

        #err=$(egrep -i "ERROR: Cannot resolve feature" $out | tail -1 | tr -dc '[:print:]' | sed -es/"ERROR:"//gi | sed "s/^[ \t]*//" | sed -es/\\.//g)
        #[[ -n $err ]] && reason="$err,config"

        var=$(egrep -A+5 -i "Error: Error: Undefined variable" $out | grep ":.*;" | tail -1 | awk -F: '{ print $2 }' | sed "s/^[ \t]*//" | sed -es/\\.//g)
        [[ -n $var ]] && reason="undefined variable ($var),code"

        err=$(egrep -i -B+5 "This is an error with npm itself" $out | grep -i "npm err" | head -1)
        [[ -n $err ]] && reason="npm error ($feature)($err),tooling"
    
        egrep -iq "enoent ENOENT:.*/tmp/conceptbuild" $out && reason="cannot find tmp file,enviro"

{ set +x; } 2>/dev/null
      fi

      # get memory and cpu
      mem=$(grep -A+50 -i '%memused' $out | grep -i "average:" | head -1 | awk '{ print $4 }' | awk -F\. '{ print $1 }')
      cpu=$(grep -A+50 -i '%idle' $out | grep -i "average:" | head -1 | awk '{ print $3 }' | awk -F\. '{ print $1 }')
      elt=$(grep -i 'Elapsed time:' $out | tail -1 | awk '{ print $NF }' | sed "s/^[ \t]*//")

      echo "$env,$ts,$id,$node,$result,$duration,$cl,$fl,$bv,$job,$reason,$cpu,$mem,$elt" | tee -a $BUILD_STATS
      rm -f $out
    done
  done
done

dos2unix -q $BUILD_STATS

# trim down the number of collections
#set -x
cd $TMP/repo/data || BailOut "Unable to cd to $TMP/repo"
git stash -q >/dev/null 2>&1
git pull -q --rebase 
git stash pop -q >/dev/null 2>&1
{ set +x; } 2>/dev/null

rm -f $BUILD_STATS.new
sort -u $BUILD_STATS | egrep -iv "=======|<<<<<<<|>>>>>>>" |
while read line
do
  [[ $line = "=======" ]] && continue
  [[ $line = "<<<<<<<"  ]] && continue
  [[ $line = ">>>>>>>"  ]] && continue
  t=$(awk -F, '{ print $2 }' <<< $line)
  [[ $t -lt $OLD ]] && continue
  echo "$line" >>  $BUILD_STATS.new
done
mv $BUILD_STATS.new $BUILD_STATS

# final sort
echo "Environment,TimeStamp,BuildId,Agent,Status,Duration,Concept_List,Feature_List,Build,URL,Reason,FailClass" > $BUILD_STATS.new
#set -x
sort -u $BUILD_STATS | egrep -iv "Environment|=======|<<<<<<<|>>>>>>>" >> $BUILD_STATS.new
mv $BUILD_STATS.new $BUILD_STATS
{ set +x; } 2>/dev/null

cd $TMP/repo/data || BailOut "Unable to cd to $TMP/repo"
#set -x
git stash -q >/dev/null 2>&1
git pull -q --rebase >/dev/null 2>&1
git stash pop -q >/dev/null 2>&1
git add $(basename $BUILD_STATS) #>/dev/null 2>&1
git commit -q -m "Update" $(basename $BUILD_STATS) >/dev/null 2>&1
git push -q -f origin HEAD:$BRANCH #>/dev/null 2>&1
{ set +x; } 2>/dev/null

cd $TMP/repo
./update-data

#[[ -z $1 ]] && jenkins-jnlp build -s generate-mfe-matrix >/dev/null 2>&1 &
cd /tmp

#/apps/mead-tools/generate-config-build-matrix.sh > /tmp/generate-config-build-matrix-$LOGNAME.out 2>&1 &

exit 0
