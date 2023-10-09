#!/bin/bash
# downloads DataStax Enterprise RPMs directly from datastax and stages them in artifactory

VERSION=$1
[ -z "$VERSION" ] && exit 1
BASE=http://rpm.datastax.com/enterprise/noarch/

DSE_PKG=$(curl -qs $BASE | awk -F '[<>]' '{ print $13 }' | egrep "dse.*rpm$" | grep "$VERSION" | sed -es/"-$VERSION.*"//g | sort -u)
DSE_AGT=$(curl -qs $BASE | awk -F '[<>]' '{ print $13 }' | egrep "datastax-agent.*rpm$" | sort -u | tail -1)

for pkg in $DSE_PKG $DSE_AGT
do
    echo "pkg: $pkg"

    if echo "$pkg" | grep -iq "datastax-agent" 
    then
      rpm=$pkg
    else
      rpm=$(curl -qs $BASE | awk -F '[<>]' '{ print $13 }' | grep "$pkg-$VERSION" | grep "rpm$" | sort | tail -1)
    fi

    echo "download $rpm"
    [ -e "$rpm" ] || curl -qskO $BASE$rpm 

    echo "Upload $rpm to artifactory"
    artifact-upload $rpm com/datastax/dse/$VERSION 

    rm -f $rpm $pkg-$VERSION.rpm
done

