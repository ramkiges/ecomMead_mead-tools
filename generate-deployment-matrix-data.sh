#!/bin/bash
PATH=/apps/mead-tools:/usr/local/bin:/bin:/usr/bin:/sbin:/usr/sbin:$PATH

REPO=git@github.wsgc.com:eCommerce-Mead/deployment-matrix.git
TMP=$(mktemp -d -t tmp.$(basename $0).XXX )
#TMP=/apps/tmp/gen-dep-matrix-data;mkdir -p $TMP

BailOut() {
  [[ -n $1 && $QUIET = "false" ]] && echo "$(basename $0): $*"  >&2
  exit 255
}

cleanUp() {
  { set +x; } 2>/dev/null
  [[ -n $TMP ]] && rm -rf $TMP
}
trap cleanUp EXIT

ENV_LIST=$1
[[ -z $ENV_LIST ]] && BailOut "Need env list"

git clone -q --depth 1 $REPO $TMP || BailOut "Can't clone"
cd $TMP || BailOUt "Can't cd to $TMP"

./generate-data ${ENV_LIST}

exit
