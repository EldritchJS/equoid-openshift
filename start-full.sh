#!/bin/bash

PROJECT_NAME=equoid
GITHUB_OWNER=eldritchjs
OP_MODE=linear

if [ $# -gt 1 ];
then
    echo "Usage: $0 [project name]"
    exit
fi

if [ $# -gt 0 ];
then
    PROJECT_NAME=$1
fi

oc new-project $PROJECT_NAME || oc project $PROJECT_NAME

oc create -f https://raw.githubusercontent.com/$GITHUB_OWNER/equoid-openshift/master/fabric8-image-streams.json
oc create -f https://raw.githubusercontent.com/$GITHUB_OWNER/equoid-openshift/master/infinispan-ephemeral-template.json
oc create -f https://radanalytics.io/resources.yaml

oc create -f https://raw.githubusercontent.com/$GITHUB_OWNER/equoid-openshift/master/artemis-rc.yaml

oc new-app --template=infinispan-ephemeral \
    -l app=datagrid \
    -p APPLICATION_NAME=datagrid \
    -p NAMESPACE=`oc project -q` \
    -p APPLICATION_USER=daikon \
    -p APPLICATION_PASSWORD=daikon \
    -p MANAGEMENT_USER=daikon \
    -p MANAGEMENT_PASSWORD=daikon

oc new-app --template=oshinko-scala-spark-build-dc \
    -l app=handler-20-${OP_MODE} \
    -p SBT_ARGS=assembly \
    -p APPLICATION_NAME=equoid-data-handler-20-${OP_MODE} \
    -p GIT_URI=https://github.com/$GITHUB_OWNER/equoid-data-handler \
    -p APP_MAIN_CLASS=io.radanalytics.equoid.DataHandler \
    -e INFINISPAN_HOST=datagrid-hotrod \
    -e INFINISPAN_PORT=11222 \
    -e WINDOW_SECONDS=20 \
    -e SLIDE_SECONDS=20 \
    -e BATCH_SECONDS=20 \
    -e OP_MODE=$OP_MODE \
    -p SPARK_OPTIONS='--driver-java-options=-Dvertx.cacheDirBase=/tmp'

echo "Waiting for the imagestreamtag fuse-java"

until oc get imagestreamtag/fuse-java:latest &> /dev/null ; do
  printf "$(tput setaf 6)▮$(tput sgr0)"
  sleep 1
  oc create -f https://raw.githubusercontent.com/$GITHUB_OWNER/equoid-openshift/master/fabric8-image-streams.json
done

oc new-app \
    -l app=publisher-${OP_MODE} \
    -e OP_MODE=$OP_MODE \
    -e DATA_URL_PRIMARY=https://raw.githubusercontent.com/$GITHUB_OWNER/equoid-data-publisher/master/data/StockCodesLinear.txt \
    --image-stream=`oc project -q`/fuse-java \
    https://github.com/$GITHUB_OWNER/equoid-data-publisher 

# web-ui
BASE_URL="https://raw.githubusercontent.com/$GITHUB_OWNER/equoid-ui/master/ocp/"
curl -sSL $BASE_URL/ocp-apply.sh | \
    BASE_URL="$BASE_URL" \
    KC_REALM_PATH="web-ui/keycloak/realm-config" \
    bash -s stable

oc policy add-role-to-user edit system:serviceaccount:`oc project -q`:default
