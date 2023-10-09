## Deploys Corp build to QA and stages files for production without loading them to websun1.
## To use this script
##    - run as imageuser.
##    - edit the script replacing the buildID (20190711-015) in 2 lines directly below
##    - run it as nohup ./corp-copy-assets.sh siteasset.txt &
##
## script will copy the tmpl and msg from the buildsystem server and load to webqa2 as well as create siteasset.txt and place static
## assets in siteassets.txt on QA corp server, QA images server and production corp servers (in /tmp/).  

scp -r buildsystem-prd-rk1v.wsgc.com:/buildsystem/buildsystem-2.0-work/artifact_repository/admindp_UI/cmx-build-20211020-004/admin* .

### cat for contents in file which says toc admindptoc-cmx-build-20200220-001.txt and scp files 
cat admindptoc-cmx-build-20211020-004.txt | awk '{print $3}' | awk 'NF' > siteasset.txt


#siteasset.txt is FILENAME to be passed to the script which  will copy required site asset  files from buildsytem-prd-rk1v server 

FILENAME=$1

cat $FILENAME | while read LINE

do

      scp -r buildsystem-prd-rk1v:/buildsystem/buildsystem-2.0-work/siteasset/admindp/$LINE /apps/loaddata/admin/

done

unzip admindptmpl*

#delay 3

unzip admindpmsg*

#delay 3


## copying assets to qa corp server ###

scp -r *dpftl* *ftl* xcadm-qa1-rk1v:/tmp/

scp siteasset.txt xcadm-qa1-rk1v:/tmp/
## copy to qa image server remote location 

scp -r admindpftl-* imgqark1v:/images/ecom-images/internal/tmpl/

## copying assets to prod corp server ###

#delay 5

scp -r *dpftl* *ftl* siteasset.txt xcarck-vccn001:/tmp

#delay 5

scp -r *dpftl* *ftl* siteasset.txt wcarck-vccn001:/tmp

#delay 5

scp -r *dpftl* *ftl* siteasset.txt wcarck-vccn002:/tmp

#delay 10

scp -r *dpftl* *ftl* siteasset.txt xcaash-vccn001:/tmp

#delay 10

scp -r *dpftl* *ftl* siteasset.txt xcaash-vpcn001:/tmp
scp -r *dpftl* *ftl* siteasset.txt xcadm-prd-rk1v:/tmp
scp -r *dpftl* *ftl* siteasset.txt xcadm-prd-rk2v:/tmp

## copy ftl to prod image server

scp -r admindpftl-* img-prd-rk1v:/images/ecom-images/internal/tmpl/

scp -r admindpftl-* img-prd-ab1v:/images/ecom-images/internal/tmpl/

../loaddata_webqa2.sh ws_app_owner q1ky*519 webqa2

### ssh to corp server and run /apps/staging/unpack.sh /tmp/siteasset.txt

###../loaddata_websun1.sh ws_app_owner xxxx  websun1
