#!/bin/bash
USER=cassandra
PASS=cassandra

CASSANDRA=cassandra-dev1-rk1
#CASSANDRA=cassandra-qa1-sac3
#CASSANDRA=cassandra-qa1-rk1

#CQLVERSION_LIST="3.4.0 3.4.4"
CQLVERSION_LIST="3.4.4"
# captures cql version and keyspaces
for CQLVERSION in $CQLVERSION_LIST
do
    KEYSPACES=$(echo "describe keyspaces;" | cqlsh -u $USER -p $PASS --cqlversion=$CQLVERSION $CASSANDRA 2>/dev/null)
    [ -n "$KEYSPACES" ] && break
done
#[ -z "$KEYSPACES" ] && KEYSPACES="solr_admin wsi_account_profile_uat dse_security system_auth wsi_registry_foundation wsi_favorites wsi_user_identity system wsi_loyalty_uat1 wsi_account_profile wsi_user_identity_uat OpsCenter keyspace1 system_distributed dse_leases dse_perf wsi_legacy_profile wsi_registry_foundation_uat wsi_loyalty system_schema dse_system wsi_legacy_profile_uat system_traces"

if [ -z "$KEYSPACES" ]
then
    echo "Couldn't get keyspace list from $CASSANDRA"
    exit 1
fi

####
DATE=$(date +'%Y%m%d')
DATA=data-export
QUIET="--quiet"
[ -d /usr/lib/python2.7/site-packages/ ] && export PYTHONPATH=/usr/lib/python2.7/site-packages/:$PYTHONPATH
#python cassandradump/cassandradump.py --help
LABEL=$(echo $CASSANDRA | awk -F- '{ print $2 "-" $3 }')
export CQLSH_NO_BUNDLED=TRUE

for keyspace in $KEYSPACES
do
    keyspace=$(echo $keyspace | sed -es/\"//g)

    CREATE="$DATA/$LABEL/$DATE/$keyspace-create.cql"
    INSERT="$DATA/$LABEL/$DATE/$keyspace-insert.cql"

    mkdir -p $(dirname "$CREATE") $(dirname "$INSERT")

    # this creates a cql script with just CREATE statements
    [ -f "$CREATE" ] || CQLSH_NO_BUNDLED=TRUE python cassandradump/cassandradump.py $QUIET --protocol-version 4 --username $USER --password $PASS --host $CASSANDRA --keyspace "$keyspace" --no-insert --export-file "$CREATE"  &

    # this creates a cql script with just INSERT statements
    [ -f "$INSERT" ] || CQLSH_NO_BUNDLED=TRUE python cassandradump/cassandradump.py $QUIET --protocol-version 4 --username $USER --password $PASS --host $CASSANDRA --keyspace "$keyspace" --no-create --export-file "$INSERT"  &
done

