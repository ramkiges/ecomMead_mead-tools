#!/bin/bash
PATH=/apps/mead-tools:/apps:/apps/java/bin:/apps/jdk8/bin:/apps/jdk7/bin:/usr/local/bin:/bin:/usr/bin:/sbin:/usr/sbin:~/bin:/wsgc/bin:$PATH
TIMEOUT=5
export CLASSPATH=~/bin:/apps:/wsgc/bin:$CLASSPATH

BailOut() {
	[ -n "$1" ] && echo "$1" 
	echo "Usage: $(basename $0) <host:port>"
	echo "       $(basename $0) <host> <port>"
	exit 1
}

exitUp() {
	[ -n "$1" ] && msg="[$1]"
	echo "Yes $msg [$(hostname) -> $HOST:$PORT]" 
	exit 0
}

exitDown() {
	[ -n "$1" ] && msg="[$1]"
	echo "No  $msg [$(hostname) -> $HOST:$PORT]"
	exit 1
}

NC=$(which nc 2>/dev/null)
[ -z "$NC" ] && BailOut "Can't find 'nc'"
[ -z "$1" ] && BailOut 

# I did this so I can be lazy and use a URL instead of a hostname
INPUT=$(echo "$1" | sed -e s/https://g -e s/tcp://g -e s/http://g -e s!/!' '!g | awk '{ print $1 }')

# temporary - the [] are actually for an array of values
#INPUT=$(echo "$INPUT" | sed -es/\\[//g)
#INPUT=$(echo "$INPUT" | sed -es/\\]//g)

if echo "$INPUT" |grep -iq ":" 
then
	HOST=$(echo "$INPUT" | awk -F: '{ print $1 }') 
	PORT=$(echo "$INPUT" | awk -F: '{ print $2 }') 
else 
	HOST=$(echo "$1" | sed -e s/https://g -e s/tcp://g -e s/http://g -e s!/!' '!g | awk '{ print $1 }')
	PORT=$2
fi

#[ -z "$PORT" ] && BailOut "Need port"
if [ -z "$PORT" ] 
then
	if echo "$1" | grep -iq "https" 
	then
		# am I making an assumption here?
		PORT=443
	else
		PORT=80
	fi
fi

[ "$PORT" = "ping" ] && PORT="icmp"

[ "$HOST" = "localhost" ] && HOST=127.0.0.1

if echo "$HOST" | grep -iq "^[a-z]"
then
	nslookup $HOST >/dev/null 2>&1
	[ $? -ne 0 ] && exitDown "Invalid host"
fi

if [ -n "$(echo "$1" | grep -i 'https')" -a "$PORT" != "80" -a "$PORT" != "8080" ]
then
	java SSLPoke $HOST $PORT </dev/null >/dev/null 2>&1
    #openssl s_client -showcerts -connect $HOST:$PORT </dev/null
    #openssl s_client -showcerts -connect stlrck-virh007.wsgc.com:8081 2>&1 </dev/null
	[ $? -eq 0 ] && exitUp "SSL"
	exitDown "SSL"
fi

if [ "$PORT" = "icmp" ]
then
	ping -c 2 $HOST >/dev/null 2>&1
	[ $? -eq 0 ] && exitUp 
	exitDown 
fi

nc -w $TIMEOUT -v $HOST $PORT </dev/null >/dev/null 2>&1
[ $? -eq 0 ] && exitUp
exitDown

