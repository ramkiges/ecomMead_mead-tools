#!/bin/bash
# This script creates an HTML table matrix of deployments
# this script runs in /apps/scripts/env_summary
# https://github.wsgc.com/tfitzpatrick/release-tools/blob/master/release-matrix.sh
PATH=/bin:/usr/bin:/sbin:/usr/sbin:/usr/local/bin:/apps:/apps/scripts/env_summary:~/bin
TIMEOUT="--connect-timeout 10  --max-time 15"
FRONTEND="https://repos.wsgc.com/svn/devops/application/frontend-2.1"
JENKINS_JOBS=git@github.wsgc.com:eCommerce-DevOps/jenkins-jobs.git
REPO=https://snapshotrepo.wsgc.com/artifactory/snapshotrepo/com/wsgc/devops/datastax/
LOGIN="pkqaenv:Ca8tWh33l"
SLAVE="ecombuild"
TMP=/tmp/dse-matrix

CLUSTER_REPOS="\
    git@github.wsgc.com:eCommerce-DevOps/datastax-dev-config.git \
    git@github.wsgc.com:eCommerce-DevOps/datastax-qa-config.git \
    git@github.wsgc.com:eCommerce-DevOps/datastax-uat-config.git \
    git@github.wsgc.com:eCommerce-DevOps/datastax-preprd-config.git \
    git@github.wsgc.com:eCommerce-DevOps/datastax-prd-config.git \
"

#CLUSTER_REPOS="git@github.wsgc.com:eCommerce-DevOps/datastax-dev-config.git"

# this is the Confluence space in which the page will reside
DOC_SPACE="ES"
PAGENAME="DSE Cassandra Matrix"

# Confluence constants
basedir="/apps/scripts/env_summary"
cclidir="$basedir/atlassian-cli-3.2.0"

BailOut() {
	[ -n "$1" ] && echo "Error: $*"
	exit 1
}

HTML() {
	echo "$*" >> $OUTFILE
}

OUTFILE=/tmp/dse-matrix.html
rm -f $OUTFILE

for repo in $CLUSTER_REPOS
do
    label=$(basename "$repo" | sed -es/\.git//g -es/datastax-//g -es/-config//g)
    echo "$repo -> $label"

    rm -rf $TMP/$label
    mkdir -p $TMP/$label
    git clone $repo $TMP/$label >/dev/null 2>&1 || exit 1

    HTML "<table border='1' width='100%'>"

    cd $TMP/$label       
    for module in $(grep '<module' pom.xml | awk -F '[<>]' '{ print $3 }')
    do
        echo "  module: $module"
        HTML 
        HTML "  <tr><th colspan='8' style='text-align:center'>$label - $module</th></tr>"
        HTML "  <tr>"
        HTML "   <th>Node</th>"   
        HTML "   <th>Hostname</th>"   
        HTML "   <th>IP</th>"   
        HTML "   <th>Devops Package</th>"   
        HTML "   <th>DSE Package</th>"   
        HTML "   <th>CPU</th>"   
        HTML "   <th>RAM</th>"   
        HTML "   <th>Disk</th>"   
        HTML "  </tr>"
        cd $TMP/$label/$module
        for node in $(grep "<dse.cassandra.*ip>" pom.xml )
        do
            host=$(echo "$node" | awk -F '[<>]' '{ print $2 }' | sed -es/dse.cassandra.//g -es/\.ip//g)
            ip=$(echo "$node" | awk -F '[<>]' '{ print $3 }')
            host $ip | grep -iq vio && continue
            wsikey $ip #|| continue

            #pkg=$(ssh -q $ip "rpm -qa | grep -i 'wsgc-devops.*datastax'" | awk -F '-201[89]' '{ print $1 }')
            pkg=$(ssh -q $ip "rpm -qa | grep -i 'wsgc-devops.*datastax'" | awk -F_ '{ print $1 }')
            dse=$(ssh -q $ip "rpm -qa | grep -i 'dse-full' | sed -es/\.noarch//g")
            name=$(host $ip 2>/dev/null | egrep -vi "NXDOMAIN" | awk '{ print $NF }' | awk -F\. '{ print $1 }')
            [ -z "$name" ] && name=$(ssh -q $ip 'hostname --short')
            link=$(echo "$pkg" | awk -F '-5' '{  print $1 }')

            cpu=$(ssh -q $ip "nproc")
            mem=$(ssh -q $ip "free -h|grep -i mem:|awk '{ print \$2 }'")
            dsk=$(ssh -q $ip "df -hP | egrep -i 'database|logs' | awk '{ print \$2,\$6 }'")
            dsk="${dsk//$'\n'/<br/>}"

            echo "      host:$host ip:$ip   name:$name  $pkg    $link   $cpu    $mem $dsk"

            HTML "  <tr>"
            HTML "      <td>$host</td>"
            HTML "      <td>$name</td>"
            HTML "      <td>$ip</td>"
            HTML "      <td><a href='$REPO/$link'>$pkg</a></td>"
            HTML "      <td>$dse</td>"
            HTML "      <td>$cpu</td>"
            HTML "      <td>$mem</td>"
            HTML "      <td>$dsk</td>"
            HTML "  </tr>"
        done
        set +x
    done
    HTML "</table>"
done

chmod 777 $OUTFILE
scp -q $OUTFILE $SLAVE:/tmp

## update confluence page
set -x
ssh -q $SLAVE "sh $cclidir/confluence.sh --space "$DOC_SPACE" --title '$PAGENAME' --action storepage --file $OUTFILE --noConvert --verbose "
set +x
