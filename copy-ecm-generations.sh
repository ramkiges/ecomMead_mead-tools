#!/bin/bash
# Thom Fitzpatrick
# this script selects generation values from one env and inserts them into another
# it is still in the experimental phase
# 
# TODO: look into CMX_GENERATION_LIST
# TODO: look into ECM.ECM_HOMEPAGE_ENABLED 
# TODO WW_TEMPLATE_ARCHIVE_LOCATOR
#
export ORACLE_HOME=/opt/oracle/product/11.2.0/client_1/
export LD_LIBRARY_PATH=$ORACLE_HOME/lib

PATH=/apps/mead-tools:/apps:/bin:/usr/bin:/sbin:/usr/sbin:/usr/local/bin:/apps/jdk8/bin:/apps/java/bin:/apps/jdk7/bin:/apps/scm-tools
PATH=$PATH:$ORACLE_HOME/bin
#PATH=$PATH:/usr/lib/oracle/19.6/client64/bin
#PATH=$PATH:/opt/oracle/product/11.2.0/client_1/bin
export PATH

DEBUG=1

LOG=/apps/generation-history.log
LOG_DATE=$(date +'%Y-%m-%d %H:%M')

# oracle variables
. /apps/buildsystem/bin/env.sh

FRONTEND="https://repos.wsgc.com/svn/devops/application/frontend-2.1"
JENKINS_URL="https://ecombuild.wsgc.com/jenkins"
DEPLOYMENTS="https://repos.wsgc.com/svn/deployments/content/trunk/deploy/properties/"
JENKINS=$(which jenkins-jnlp 2>/dev/null)
JMX_PORT=39667
CLONE=/tmp/clone.sh
ORACLE_ERROR="selected|error:|ORA-|SP2-|Usage:|<proxy>|<logon>|^$|violated|constraint|error at line"
rm -f $CLONE

BRAND=$1
SRC_ENV=$2
DST_ENV=$3
COMMIT=$4

# Jira icons
ICON_FAIL=" (x) "
ICON_SUCC=" (/) "
ICON_WARN=" (!) "
ICON_INFO=" (i) "

umask 000
SKIP_LIST=
#SKIP_LIST="PROMO_VIZ"
DEFAULT_LIST="ECMPROMOS ECMCS ECMHOMEPAGE ECMMSG ECMPAGES ENDECA HOMEPAGE PROMOS REGLANDING RECIPE ODIS ODIS_SERVICE IDEAS CAT TMPL MISC MSG PROMO_VIZ "
ECM_LIST="ECMMSG|ECMPAGES|ECMCS|ECMHOMEPAGE|CAT|ENDECA|RECIPE|ECMPROMOS|PROMOS|ODIS|TMPL|MISC|MSG|HOMEPAGE"
#echo "$(basename $0): RunBy=$RUNBY"
[[ -z $RUNBY ]] && RUNBY=${BUILD_USER_ID}

if [ -n "$TICKET" ] 
then
    TICKET=$(echo "$TICKET" | tr '[:lower:]' '[:upper:]' | sed -es/,/' '/g)
	TICKET=$(echo "$TICKET" | tr '[:lower:]' '[:upper:]' | sed -es/,/' '/g)
    for jira in $TICKET
    do
	    echo "Jira: https://jira.wsgc.com/browse/$jira"
    done
fi

BailOut() {
	[ -n "$1" ] && echo "$*"
	echo "Usage: $(basename $0) <brand> <src_env> <dst_env>"
	exit 1
}

#runSQL() {
#    RESULT=$(echo "$SQL" | $SQLPLUS -S "${dbUser}/${dbPass}@(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=${dbHost})(PORT=${dbPort}))(CONNECT_DATA=(SID=${dbSID})))" | tr '\n' ' ')
#      [ -n "$RESULT" ] && echo "$RESULT" 
#}

[ -z "$BRAND" ] && BailOut "Need brand"
[ -z "$SRC_ENV" ] && BailOut "Need source DB"
[ -z "$DST_ENV" ] && DST_ENV=$SRC_ENV
[ -z "$DST_ENV" ] && BailOut "Need destination DB"

[ "$SRC_ENV" = "rgs" ] && SRC_ENV="regression"
[ "$DST_ENV" = "rgs1" ] && DST_ENV="regression"

[ "$DST_ENV" = "regression2" ] && DST_ENV="rgs2"

[ "$SRC_ENV" = "integration" ] && SRC_ENV="int1"
[ "$SRC_ENV" = "integration2" ] && SRC_ENV="int2"

# do some manipulation of the environment names
SRC_DB_ENV=$SRC_ENV
DST_DB_ENV=$DST_ENV
SRC_DB_ENV=$(get-installation $BRAND $SRC_ENV)
DST_DB_ENV=$(get-installation $BRAND $DST_ENV)

# special case for prod
if [[ $SRC_DB_ENV =~ prod ]]
then
  echo "*** Copying $BRAND generations from $SRC_DB_ENV to $DST_DB_ENV ***"
  eval copy-prod-generations $BRAND $DST_DB_ENV $TICKET
  exit $?
fi

for script in getschema getdb geturls sqlplus
do
    which $script >/dev/null 2>&1 || BailOut "Can't find $script"
done

SITE=$(brand2site $BRAND $ENV)
[ -z "$SITE" ] && BailOut "Invalid brand"
# grab sites for src and dest
SRC_SITE=$(brand2site $BRAND $SRC_ENV)
DST_SITE=$(brand2site $BRAND $DST_ENV)
[[ -z $SRC_SITE ]] && BailOut "Unable to get siteID for src $SRC_ENV"
[[ -z $DST_SITE ]] && BailOut "Unable to get siteID for dst $DST_ENV"

for dir in /wsgc/bin /apps ~/bin
do
	[ -f $dir/jmxclient.jar ] && { JMX_JAR=$dir/jmxclient.jar; break; }
done

#SRC_SUMMARY=$(geturls $BRAND $SRC_ENV | grep -i summary.html | awk '{ print $NF }')
#[[ -z $SRC_SUMMARY ]] && echo "Can't figure out the summary page for $BRAND $SRC_ENV"

#DST_SUMMARY=$(geturls $BRAND $DST_ENV | grep -i summary.html | awk '{ print $NF }')
#[[ -z $DST_SUMMARY ]] && echo "Can't figure out the summary page for $BRAND $DST_ENV"

SRC_OWNER=$(getschema $BRAND $SRC_ENV)
DST_OWNER=$(getschema $BRAND $DST_ENV)

[[ $BRAND = "corp" ]] && { SRC_OWNER=WS_APP_OWNER; DST_OWNER=WS_APP_OWNER; }

[ -z "$SRC_OWNER" ] && BailOut "Can't find schema for source ($BRAND $SRC_ENV)"
[ -z "$DST_OWNER" ] && BailOut "Can't find schema for destination ($BRAND $DST_ENV)"

#echo "SRC Owner: $SRC_OWNER"
#echo "DST Owner: $DST_OWNER"

# getdb is a script which returns the db connections params for a given schema
DST_DB=$(getdb $DST_OWNER)
[ -z "$DST_DB" ] && BailOut "Can't get creds for $DST_OWNER $BRAND $DST_ENV"
DST_dbHost=$(echo "$DST_DB" | awk -F\| '{ print $1 }')
DST_dbOwner=$(echo "$DST_DB" | awk -F\| '{ print $2 }' | tr '[:lower:]' '[:upper:]')
DST_dbUser=$(echo "$DST_DB" | awk -F\| '{ print $3 }')
DST_dbPass=$(echo "$DST_DB" | awk -F\| '{ print $4 }')
DST_dbSID=$(echo "$DST_DB" | awk -F\| '{ print $5 }' | tr '[:lower:]' '[:upper:]')
DST_dbPort=$(echo "$DST_DB" | awk -F\| '{ print $6 }')
DST_dbTable=$(echo "$DST_DB" | awk -F\| '{ print $7 }')
DST_dbConnect=$(echo "$DST_DB" | awk -F\| '{ print $10 }')

SRC_DB=$(getdb $SRC_OWNER)
[ -z "$SRC_DB" ] && BailOut "Can't get creds for $SRC_OWNER $BRAND $SRC_ENV"
SRC_dbHost=$(echo "$SRC_DB" | awk -F\| '{ print $1 }')
SRC_dbOwner=$(echo "$SRC_DB" | awk -F\| '{ print $2 }' | tr '[:lower:]' '[:upper:]')
SRC_dbUser=$(echo "$SRC_DB" | awk -F\| '{ print $3 }')
SRC_dbPass=$(echo "$SRC_DB" | awk -F\| '{ print $4 }')
SRC_dbSID=$(echo "$SRC_DB" | awk -F\| '{ print $5 }' | tr '[:lower:]' '[:upper:]')
SRC_dbPort=$(echo "$SRC_DB" | awk -F\| '{ print $6 }')
SRC_dbTable=$(echo "$SRC_DB" | awk -F\| '{ print $7 }')
SRC_dbConnect=$(echo "$DST_DB" | awk -F\| '{ print $10 }')

DST_CONNECT="${DST_dbUser}/${DST_dbPass}@(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=${DST_dbHost})(PORT=${DST_dbPort}))(CONNECT_DATA=($DST_dbConnect=${DST_dbSID})))"
SRC_CONNECT="${SRC_dbUser}/${SRC_dbPass}@(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=${SRC_dbHost})(PORT=${SRC_dbPort}))(CONNECT_DATA=($SRC_dbConnect=${SRC_dbSID})))"

# make sure the .tnsnames.ora file has our SIDs
grep -iwq "$SRC_dbSID" $HOME/.tnsnames.ora || BailOut "Source DB SID $SRC_dbSID not found in $HOME/.tnsnames.ora"
grep -iwq "$DST_dbSID" $HOME/.tnsnames.ora || BailOut "Destination DB SID $DST_dbSID not found in $HOME/.tnsnames.ora"

SRC_INST=$(get-installation $BRAND $SRC_ENV)
[[ -z $SRC_INST ]] && SRC_INST=$SRC_DB_ENV
DST_INST=$(get-installation $BRAND $DST_ENV)
[[ -z $DST_INST ]] && DST_INST=$DST_DB_ENV
[[ $DST_INST =~ jukebox ]] && DST_INST=prod

# perf snowflake
#echo "Looking for DST env overrides in $DST_ENV/$BRAND.properties"
#dbHost=$(svn cat $DEPLOYMENTS/$DST_ENV/$BRAND.properties | grep "DBHost" | grep -iv "^#" | awk -F= '{ print $2 }')
#[ -n "$dbHost" ] && DST_dbHost=$dbHost
#dbSID=$(svn cat $DEPLOYMENTS/$DST_ENV/$BRAND.properties | grep "DBInst" | grep -iv "^#" | awk -F= '{ print $2 }')
#[ -n "$dbSID" ] && DST_dbSID=$dbSID
#dbUser=$(svn cat $DEPLOYMENTS/$DST_ENV/$BRAND.properties | grep "DBUid" | grep -iv "^#" | awk -F= '{ print $2 }')
#[ -n "$dbUser" ] && DST_dbUser=$dbUser
#dbPort=$(svn cat $DEPLOYMENTS/$DST_ENV/$BRAND.properties | grep "DBPort" | grep -iv "^#" | awk -F= '{ print $2 }')
#[ -n "$dbPort" ] && DST_dbPort=$dbPort
#dbPass=$(svn cat $DEPLOYMENTS/$DST_ENV/$BRAND.properties | grep "DBPwd" | grep -iv "^#" | awk -F= '{ print $2 }')
#[ -n "$dbPass" ] && DST_dbPass=$dbPass

[[ -n $TICKET ]] && jira-comment "$TICKET" "${ICON_INFO}$(basename $0) Copy generations for _${BRAND}_ *from* _${SRC_DB_ENV}_ *to* _${DST_DB_ENV}_ ($DST_ENV)"

# if they select TMPL/MISC/MSG then do *not* run content build
[[ $CMX = "true" ]] && DEPLOY_CONTENT="De-selected because TMPL/MISC/MSG was selected"
[[ $TMPL = "true" ]] && DEPLOY_CONTENT="De-selected because TMPL/MISC/MSG was selected"
[[ $MISC = "true" ]] && DEPLOY_CONTENT="De-selected because TMPL/MISC/MSG was selected"
[[ $MSG = "true" ]] && DEPLOY_CONTENT="De-selected because TMPL/MISC/MSG was selected"

[[ -n $SUBSYSTEM ]] &&  echo "SubSystem:         $SUBSYSTEM"
[[ -n $GENERATION ]] && echo "Generation:        $GENERATION"
[[ -n $COPYASSETS ]] && echo "CopyAssets:        $COPYASSETS"
#echo "Copy generations for $BRAND FROM $SRC_ENV ($SRC_INST) TO $DST_DB_ENV ($DST_INST) "
echo "ECM:  $(get-ecm-env $BRAND $DST_ENV | tr '\n' ' ')"
echo "SRC:  $SRC_dbHost  $SRC_dbSID    $SRC_dbOwner  $SRC_dbUser $SRC_dbConnect $SRC_SITE"
echo "DST:  $DST_dbHost  $DST_dbSID    $DST_dbOwner  $DST_dbUser $DST_dbConnect $DST_SITE"
#echo "Options:"
[[ -n $DEPLOY_CONTENT ]] && echo "Deploy CONTENT:           $DEPLOY_CONTENT"
[[ -n $DEPLOY_CONTENT ]] && echo "Deploy WAR:               $DEPLOY_WAR"
[[ -n $ADMIN ]] && echo "Update Admin (600):       $ADMIN"
#[[ -n $UPDATE_ARCHIVE_LOCATOR ]] && echo "Update ARCHIVE_LOCATOR:   $UPDATE_ARCHIVE_LOCATOR"
#[[ -n $GENERATION ]] && echo "Generation:               $GENERATION"

# get list of relevant subsystems
Q="set heading off; 
SELECT DISTINCT SUBSYSTEM FROM ${SRC_dbOwner}.WW_GENERATION_SCHEDULE 
  WHERE (SITE = '$SRC_SITE' and (installation = '$SRC_ENV' or installation = '$SRC_DB_ENV' or installation = '$SRC_INST' )) 
  ORDER BY SUBSYSTEM;"
SUBSYS_LIST_SRC=$(echo "$Q" | sqlplus -S "$SRC_CONNECT" | egrep -vi "$ORACLE_ERROR") 

Q="set heading off; 
SELECT DISTINCT SUBSYSTEM FROM ${DST_dbOwner}.WW_GENERATION_SCHEDULE 
  WHERE (SITE = '$SRC_SITE' and (installation = '$DST_ENV' or installation = '$DST_DB_ENV' or installation = '$DST_INST' )) 
  ORDER BY SUBSYSTEM;"
SUBSYS_LIST_DST=$(echo "$Q" | sqlplus -S "$DST_CONNECT" | egrep -vi "$ORACLE_ERROR") 
#[[ $DEBUG -gt 1 ]] && echo "DST subsystems: $SUBSYS_LIST_DST"

if [[ -n $SUBSYSTEM && -n $GENERATION ]]
then
  ALL_SUBSYS=$(echo "$SUBSYSTEM" | awk '{ print $1 }' | tr '[:lower:]' '[:upper:]')
  [[ $ALL_SUBSYS = "CAT" ]] && CAT=true
  [[ $ALL_SUBSYS = "TMPL" ]] && { MSG=true; MISC=true; TMPL=true; ALL_SUBSYS=CMX; }
  [[ $ALL_SUBSYS = "MISC" ]] && { MSG=true; MISC=true; TMPL=true; ALL_SUBSYS=CMX; }
  [[ $ALL_SUBSYS = "MSG" ]] && { MSG=true; MISC=true; TMPL=true; ALL_SUBSYS=CMX;}
  [[ $ALL_SUBSYS = "CMX" ]] && { MSG=true; MISC=true; TMPL=true; ALL_SUBSYS=CMX;}
  COMMENT="+++ Manually set $ALL_SUBSYS to $GENERATION"
else
  ALL_SUBSYS="$SUBSYS_LIST_SRC $SUBSYS_LIST_DST $DEFAULT_LIST"
  COMMENT="Copy generations for _${BRAND}_ *from* _${SRC_DB_ENV}_ *to* _${DST_DB_ENV}_
||SubSystem||Old||New||Result|| "
fi

[[ $SUBSYSTEM = "CMX" || $SUBSYSTEM = "MSG" || $SUBSYSTEM = "MISC" || $SUBSYSTEM = "TMPL" ]] && CMX=true

#if [[ $ALL_SUBSYS =~ CMX ||  $ALL_SUBSYS =~ MSG ||  $ALL_SUBSYS =~ MISC || $ALL_SUBSYS =~ TMPL ]]
if [[ $CMX = "true" ]]
then
  ALL_SUBSYS="$ALL_SUBSYS MSG MISC TMPL"
  MSG=true 
  MISC=true 
  TMPL=true
fi
ALL_SUBSYS=$(echo "$ALL_SUBSYS" | xargs -n1 | sort -u)

[[ -n $CMX ]] && echo "CMX: $CMX $MSG/$MISC/$TMPL"
# for updating existing envs - this seems to work well
for SUBSYS in $ALL_SUBSYS
do
  [[ $SUBSYS =~ CMX ]] && continue
  echo "$SUBSYS" | egrep -qi "^[A-Z]" || continue

  # optional TMPL/MISC/MSG copy
#echo "[$SUBSYS]"
  case $SUBSYS in 
    CAT )  [[ $CAT = "true" ]]  || continue ;;
    TMPL ) [[ $TMPL = "true" ]] || continue ;;
    MISC ) [[ $MISC = "true" ]] || continue ;;
    MSG )  [[ $MSG = "true"  ]] || continue ;;
  esac

  echo "*****"
  /bin/echo -ne "SubSys: $SUBSYS "
  echo "$SUBSYS" | egrep -iqw "$SKIP_LIST" && { echo " *** Skipping ***"; continue; }
  #[[ -n $TICKET && $SUBSYS =~ ECM ]] && jira-label "$TICKET" "Update-ECM-generation"
  #[[ -n $TICKET && $SUBSYS =~ MSG ]] && jira-label "$TICKET" "Update-CMX-generation"
  #[[ -n $TICKET && $SUBSYS =~ MISC ]] && jira-label "$TICKET" "Update-CMX-generation"
  #[[ -n $TICKET && $SUBSYS =~ TMPL ]] && jira-label "$TICKET" "Update-CMX-generation"
  echo

	OG_SQL="set heading off; 
select * from 
(SELECT GENERATION FROM ${DST_dbOwner}.WW_GENERATION_SCHEDULE WHERE (SITE = '$DST_SITE' and installation = '$DST_INST' and subsystem = '$SUBSYS') order by START_TIME desc)
where rownum = 1;"
    #[[ $DEBUG -gt 1 ]] && echo "OG_SQL: $OG_SQL"

	NG_SQL="set heading off; 
select * from 
(SELECT GENERATION FROM ${SRC_dbOwner}.WW_GENERATION_SCHEDULE WHERE (SITE = '$SRC_SITE' and installation = '$SRC_INST' and subsystem = '$SUBSYS') order by START_TIME desc)
where rownum = 1;"
    #[[ $DEBUG -gt 1 ]] && echo "NG_SQL:$NG_SQL"

    # grab current generation from destination
    OLDGEN=$(echo "$OG_SQL" | sqlplus -S "${DST_dbUser}/${DST_dbPass}@(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=${DST_dbHost})(PORT=${DST_dbPort}))(CONNECT_DATA=($DST_dbConnect=${DST_dbSID})))" | egrep -iv "$ORACLE_ERROR" | tr '\n' ' ' | awk '{ print $1 }' )
    [[ $OLDGEN =~ ^[0-9] ]] || OLDGEN=

    # grab the new generation from the source
    NEWGEN=$(echo "$NG_SQL" | sqlplus -S "${SRC_dbUser}/${SRC_dbPass}@(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=${SRC_dbHost})(PORT=${SRC_dbPort}))(CONNECT_DATA=($SRC_dbConnect=${SRC_dbSID})))" | egrep -iv "$ORACLE_ERROR" | tr '\n' ' ' | awk '{ print $1 }' )
    [[ $NEWGEN =~ ^[0-9] ]] || NEWGEN=

    [[ -n $GENERATION ]] && NEWGEN=$GENERATION
    [ -z "$NEWGEN" -a -n "$OLDGEN" ] && { echo "+++ New generation is blank, using old generation +++"; NEWGEN=$OLDGEN; }
    [ -z "$NEWGEN" ] && continue
    [ -z "$OLDGEN" ] && OLDGEN="<none>"

    [[ -n $GENERATION ]] && { echo "Manual override: $GENERATION"; NEWGEN=$GENERATION; }

	I="set define off;
INSERT INTO ${DST_dbOwner}.WW_GENERATION_SCHEDULE 
	(GENERATION, SITE, INSTALLATION, SUBSYSTEM, START_TIME, REFRESH) 
VALUES 
	($NEWGEN, $DST_SITE, '$DST_INST', '$SUBSYS', SYSDATE, 0);
commit;"
	echo "$BRAND $DST_INST $SUBSYS: $OLDGEN -> $NEWGEN "
  #[[ $DEBUG -gt 1 ]] && echo "I: $I"

  [[ $OLDGEN != $NEWGEN ]] && echo "$LOG_DATE,$BRAND,$DST_ENV,$SUBSYS,$OLDGEN,$NEWGEN,$BUILD_USER_ID $RUNBY,$BUILD_URL,$TICKET" >> $LOG

	ERROR="/tmp/$(basename $0)-$BRAND-$SUBSYS-$DST_INST-sql.err"
	echo "$I" > $ERROR
  echo  "${DST_dbUser}/${DST_dbPass}@(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=${DST_dbHost})(PORT=${DST_dbPort}))(CONNECT_DATA=($DST_dbConnect=${DST_dbSID})))" >> $ERROR
	echo "$I" | sqlplus -S "${DST_dbUser}/${DST_dbPass}@(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=${DST_dbHost})(PORT=${DST_dbPort}))(CONNECT_DATA=($DST_dbConnect=${DST_dbSID})))" #>> $ERROR 2>&1 
	if [ $? -eq 0 ] 
	then
		echo " - Ok"
        ICON=$ICON_SUCC
        rm -f $ERROR
      if [[ $SRC_ENV = "vqa" || $SRC_ENV = "vprod" || $SRC_ENV = "vaktest" ]] 
      then
        G="${NEWGEN:0:1}"
        #[[ $G = "8" ]] && echo "asset-clone $NEWGEN" 
        [[ $G = "8" || $G = "2" ]] && echo "/apps/mead-tools/asset-clone $NEWGEN" >> $CLONE
      fi
	else
		echo " - Update failed"
        ICON=$ICON_FAIL
	fi
    #COMMENT="$COMMENT
#${ICON}$SUBSYS$OLDGEN -> $NEWGEN "
    COMMENT="$COMMENT
|$SUBSYS|$OLDGEN|$NEWGEN|$ICON|"

# admintool hack
    if [[ $ADMIN = "true" ]]
    then
	    echo "*** Updating Admin $DST_DB_ENV ***"
	    I3="set define off;
INSERT INTO ${DST_dbOwner}.WW_GENERATION_SCHEDULE 
	(GENERATION, SITE, INSTALLATION, SUBSYSTEM, START_TIME, REFRESH) 
VALUES 
	($NEWGEN, 600, '$DST_INST', '$SUBSYS', SYSDATE, 0);
commit;"
        #[[ $DEBUG -gt 1 ]] && echo "$I3" 
        echo "$I3" >> $ERROR
	    echo "$I3" | sqlplus -S "${DST_dbUser}/${DST_dbPass}@(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=${DST_dbHost})(PORT=${DST_dbPort}))(CONNECT_DATA=($DST_dbConnect=${DST_dbSID})))" >> $ERROR 2>&1 
    fi

    if [ "$SUBSYS" = "CAT" -a -n "$NEWGEN" ] 
    then
        ## tell DP to invalidate its produce cache
        #if [ -n "$JMX_JAR" ]
        #then
        #    HOST=$(geturls $BRAND $DST_ENV|grep -i "host:" | awk -F: '{ print $2 }' | awk '{ print $1 }')
        #    if [ -n "$HOST" ]
        #    then
        #        for job in availabilityCache baseSkuCache${OLDGEN}.0 checkAvailabilityCache foundationDataCache skuCache${OLDGEN}.0
        #        do
        #         echo "Invalidating $HOST DP cache: $job"
        #         java -jar $JMX_JAR - $HOST:39667 com.wsgc.ecommerce.$BRAND:type=Cache,name=$job removeAll >/dev/null 2>&1
        #     done
        #    else
        #        echo "Can't figure out the host for $BRAND $DST_ENV"
        #    fi
        #fi

        echo "+++ Update cat generation:  $JENKINS_URL/job/wcm-update-generation"
        eval $JENKINS build wcm-update-generation -p SITE=$BRAND -p ENV=$DST_ENV -p GENERATION=$NEWGEN -p TICKET=$TICKET
    fi

    # only update WW_ARTIFACT_ARCHIVE_LOCATOR for these subsystems 
    WW_ECM=$(echo "$SUBSYS" | egrep -wi "$ECM_LIST|ODIS_SERVICE")
    if [ -z "$NEWGEN" ]
    then
      echo "*** new generation is empty"
    fi

    [[ $SUBSYS = "TMPL" || $SUBSYS = "MISC" || $SUBSYS = "MSG" ]] && TABLE="WW_TEMPLATE_ARCHIVE_LOCATOR" || TABLE="WW_ARTIFACT_ARCHIVE_LOCATOR"
    if [ -n "$WW_ECM" -a -n "$NEWGEN" -a "$NEWGEN" != "0" ]
    then
        A_LIST_SQL="set heading off;
set define off;"
        [[ $TABLE = "WW_ARTIFACT_ARCHIVE_LOCATOR" ]] && A_LIST_SQL="$A_LIST_SQL
select ARTIFACT_ID from ${SRC_dbOwner}.$TABLE where GENERATION='$NEWGEN';"
        [[ $TABLE = "WW_TEMPLATE_ARCHIVE_LOCATOR" ]] && A_LIST_SQL="$A_LIST_SQL
select GENERATION from ${SRC_dbOwner}.$TABLE where GENERATION='$NEWGEN';"

        #[[ $DEBUG -gt 1 ]] && echo "A: $A_LIST_SQL"
        A_LIST=$(echo "$A_LIST_SQL" | sqlplus -S "$SRC_CONNECT" | egrep -iv "$ORACLE_ERROR" | sort -u)

        echo "+++ Updating $TABLE - $SUBSYS [$A_LIST] ***"
        for artifact in $A_LIST
        do
          if [[ $TABLE = "WW_ARTIFACT_ARCHIVE_LOCATOR" ]] 
          then
            # capture columns from source DB - this can be done better
            A_PATH_SQL="set heading off;
select ARCHIVE_PATH from ${SRC_dbOwner}.$TABLE where ARTIFACT_ID='$artifact' and GENERATION='$NEWGEN' and rownum=1;" 
            A_SIZE_SQL="set heading off;
select ARCHIVE_SIZE from ${SRC_dbOwner}.$TABLE where ARTIFACT_ID='$artifact' and GENERATION='$NEWGEN' and rownum=1;" 
            A_HASH_SQL="set heading off;
select ARCHIVE_HASH from ${SRC_dbOwner}.$TABLE where ARTIFACT_ID='$artifact' and GENERATION='$NEWGEN' and rownum=1;" 

            A_PATH=$(echo "$A_PATH_SQL" | sqlplus -S "$SRC_CONNECT" | egrep -iv "$ORACLE_ERROR" | tr '\n' ' ' | awk '{ print $1 }' )
            A_SIZE=$(echo "$A_SIZE_SQL" | sqlplus -S "$SRC_CONNECT" | egrep -iv "$ORACLE_ERROR" | tr '\n' ' ' | awk '{ print $1 }' )
            A_HASH=$(echo "$A_HASH_SQL" | sqlplus -S "$SRC_CONNECT" | egrep -iv "$ORACLE_ERROR" | tr '\n' ' ' | awk '{ print $1 }' )

            # insert into WW_ARTIFACT_ARCHIVE_LOCATOR
            I="set define off;
INSERT INTO ${DST_dbOwner}.$TABLE
(SITE, SUBSYSTEM, GENERATION, ARCHIVE_PATH, ARCHIVE_SIZE, ARCHIVE_HASH, ARTIFACT_ID)
VALUES
($DST_SITE, '$SUBSYS', $NEWGEN, '$A_PATH', $A_SIZE, '$A_HASH', '$artifact');
commit;"
          fi
          
          if [[ $TABLE = "WW_TEMPLATE_ARCHIVE_LOCATOR" ]] 
          then
            # capture columns from source DB - this can be done better
            A_PATH_SQL="set heading off;
select ARCHIVE_PATH from ${SRC_dbOwner}.$TABLE where GENERATION='$NEWGEN' and rownum=1;" 
            A_SIZE_SQL="set heading off;
select ARCHIVE_SIZE from ${SRC_dbOwner}.$TABLE where GENERATION='$NEWGEN' and rownum=1;" 
            A_HASH_SQL="set heading off;
select ARCHIVE_HASH from ${SRC_dbOwner}.$TABLE where GENERATION='$NEWGEN' and rownum=1;" 

            A_PATH=$(echo "$A_PATH_SQL" | sqlplus -S "$SRC_CONNECT" | egrep -iv "$ORACLE_ERROR" | tr '\n' ' ' | awk '{ print $1 }' )
            A_SIZE=$(echo "$A_SIZE_SQL" | sqlplus -S "$SRC_CONNECT" | egrep -iv "$ORACLE_ERROR" | tr '\n' ' ' | awk '{ print $1 }' )
            A_HASH=$(echo "$A_HASH_SQL" | sqlplus -S "$SRC_CONNECT" | egrep -iv "$ORACLE_ERROR" | tr '\n' ' ' | awk '{ print $1 }' )

            # insert into WW_TEMPLATE_ARCHIVE_LOCATOR
            I="set define off;
INSERT INTO ${DST_dbOwner}.$TABLE
(SITE, GENERATION, ARCHIVE_PATH, ARCHIVE_SIZE, ARCHIVE_HASH)
VALUES
($DST_SITE, $NEWGEN, '$A_PATH', $A_SIZE, '$A_HASH');
commit;"
          fi

          #[[ $DEBUG -gt 1 ]] && echo "$I"
          echo "$I" | sqlplus -S "$DST_CONNECT" >/dev/null 2>&1
        done
      else
        echo "--- Not updating $TABLE - $SUBSYS ($NEWGEN)"
    fi

    if [[ $SUBSYS =~ ECM && $COPYASSETS = "true" ]] 
    then
      if [[ $OLDGEN = "$NEWGEN" ]]
      then 
        #echo "New ECM generation is the same as the old one - skipping copy"
        jenkins-jnlp build -s stage-ecm-generation -p Brand=$BRAND -p Environment=$DST_ENV -p Generation=$NEWGEN -p SubSystem=$SUBSYS
      else
        jenkins-jnlp build -s stage-ecm-generation -p Brand=$BRAND -p Environment=$DST_ENV -p Generation=$NEWGEN -p SubSystem=$SUBSYS
      fi
    fi
done

[[ -n $TICKET ]] && jira-comment "$TICKET" "$COMMENT"

if [[ $DEPLOY_CONTENT = "true" || $DEPLOY_WAR = "true" ]]
then
  echo "*** Deploy ***"
  [[ -z $JENKINS ]] && { echo "Can't find 'jenkins-jnlp'"; exit 0; }

  [[ $DEPLOY_CONTENT =~ true ]] && DEPLOY_CONTENT="-p Options=Deploy-Content" || DEPLOY_CONTENT=
  #[[ $DEPLOY_CONTENT =~ true ]] && DEPLOY_CONTENT="-p Options=Force-Content"
  [[ $DEPLOY_WAR =~ true ]] && DEPLOY_WAR="-p Options=Deploy-War" || DEPLOY_WAR=

  eval $JENKINS build CheckEnv \
    -p Brand=$BRAND \
    -p Environment=$DST_ENV \
    -p Options=Clear-Logs \
    -p Options=Rebuild-MFE \
    -p Ticket=$TICKET \
    $DEPLOY_WAR \
    $DEPLOY_CONTENT 
fi

if [[ $ALL_SUBSYS =~ CMX ]] 
then
  bgb=$(get-bgb-host $BRAND $DST_ENV | awk -F\. '{ print $1 }' | sed -es/-rk1v//g -es/-sac1v//g -es/bgb-//g)
  jenkins-jnlp build stage-cmx-generation -p Brand=$BRAND -p Environment=$DST_ENV -p Generation=$GENERATION -p BGB=$bgb 
fi

#if [ "$REBASELINE" = "true" ]
#then
#  echo "*** Rebaseline ***"
#  for ecmhost in ecmagentintrk1v.wsgc.com ecmagentintrk1v.wsgc.com ecmagent-qa-rk1v.wsgc.com
#  do
#    echo "=== $ecmhost"
#    curl -sqk http://$ecmhost/rebaseline?concept=$BRAND
#    curl -sql http://$ecmhost:38667/ecmagent/application.log | tail -20 | grep -i rebaseline | tail -1
#  done
#fi

cat $CLONE 2>/dev/null

exit 0

