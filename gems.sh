#!/bin/bash

TIBEMS_ROOT=$HOME/Gems
cd $TIBEMS_ROOT

TIBEMS_JAVA=${TIBEMS_ROOT}/lib
CLASSPATH=${TIBEMS_JAVA}/jms.jar:${TIBEMS_JAVA}/jndi.jar
CLASSPATH=Gems.jar:looks-2.3.1.jar:jcommon-1.0.16.jar:jfreechart-1.0.13.jar:${TIBEMS_JAVA}/tibjms.jar:${TIBEMS_JAVA}/tibcrypt.jar:${TIBEMS_JAVA}/tibjmsadmin.jar:${CLASSPATH}
## uncomment the line below for SSL connections
#CLASSPATH=${CLASSPATH}:${TIBEMS_JAVA}/slf4j-api-1.4.2.jar:${TIBEMS_JAVA}/slf4j-simple-1.4.2.jar
#echo ${CLASSPATH}
java -classpath ${CLASSPATH} -Xmx128m -DPlastic.defaultTheme=DesertBluer com.tibco.gems.Gems gems.props >/dev/null 2>&1 &
