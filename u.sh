#!/bin/bash

MANIFEST_BRANCH=thomtest
rm -rf /tmp/manifest-qa33
hub clone -q git@github.wsgc.com:eCommerce-Mead/env-manifest.git /tmp/manifest-qa33
cd /tmp/manifest-qa33
hub remote remove origin
set -x

hub remote add devops git@github.wsgc.com:eCommerce-DevOps/env-manifest.git
hub remote add mead git@github.wsgc.com:eCommerce-Mead/env-manifest.git
hub fetch -q --all --prune

hub checkout -b $MANIFEST_BRANCH
hub push --set-upstream mead $MANIFEST_BRANCH
hub branch --set-upstream-to=devops/release release

#hub branch --all
hub rebase devops/release
