#!/bin/bash
#Script to explore snow api's
PATH=/bin:/usr/bin:/sbin:/usr/sbin:/usr/local/bin:/apps

BailOut() {
	[ -n "$1" ] && echo "$1" >&2
	echo "Usage: $(basename $0) " >&2
	exit 1
}

#Variables
#Sys id for Ecom Devops Non-Prod group 
#sys_id=0067a379db5b4b046953d411ce96190e
#password=$1

# validate SNOW creds
SNOW_CRED=$HOME/.snow
[ -z "$SNOW_CRED" ] && BailOut "SNOW cred file variable undefined (SNOW_CRED)"
[ -f "$SNOW_CRED" ] || BailOut "Can't find SNOW cred file ($SNOW_CRED)"

source $SNOW_CRED
[ -z "$SNOW_USER" ] && BailOut "Can't parse SNOW user from $SNOW_CRED"
[ -z "$SNOW_PASS" ] && BailOut "Can't parse SNOW pass from $SNOW_CRED"
[ -z "$SNOW_ID" ] && BailOut "Can't parse SNOW ID from $SNOW_CRED"
[ -z "$SNOW_URL" ] && BailOut "Can't parse SNOW URL from $SNOW_CRED"

set -x
curl -k "https://wsi.service-now.com/api/now/table/incident/$SNOW_ID" --request GET --header "Accept:application/json" --user "$SNOW_USER:$SNOW_PASS"
set +x


