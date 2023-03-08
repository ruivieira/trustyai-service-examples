#!/bin/env bash

# CHANGE ME!
export QUAY_REPO="ruimvieira" # The repo where you to push the images to. e.g. quay.io/*ruimvieira*/modelmesh-test
export MM_TAG="0.0.1"
# END CHANGE ME.

ROOT=$(git rev-parse --show-toplevel)

cd /tmp || exit

if [ -d "/tmp/modelmesh" ]
then
    read -r -p "/tmp/modelmesh already exists. Delete? (y/n/c) " yn
    case $yn in
        y ) rm -Rf /tmp/modelmesh;
            git clone git@github.com:kserve/modelmesh.git;
            cd modelmesh || exit;
            git fetch origin pull/84/head:84;
            git checkout 84;
            echo "Hardcoding endpoint";
            sed -i "/String payloadProcessorsDefinitions = /c\String payloadProcessorsDefinitions = \"http://trustyai-service.modelmesh-serving/consumer/kserve/v2\";" /tmp/modelmesh/src/main/java/com/ibm/watson/modelmesh/ModelMesh.java
            export TAG_LATEST="quay.io/${QUAY_REPO}/modelmesh-test:${MM_TAG}";
            mvn clean install -DskipTests;
            docker build . -t $QUAY_REPO/modelmesh-test:${MM_TAG};
            docker tag $QUAY_REPO/modelmesh:${MM_TAG} $TAG_LATEST;
        docker push $TAG_LATEST;;
        c ) echo "continuing...";;
        n ) echo "exiting...";
        exit;;
        * ) echo "invalid response";
        exit 1;;
    esac
fi

cd /tmp || exit
if [ -d "/tmp/modelmesh-serving" ]
then
    read -r -p "/tmp/modelmesh-serving already exists. Delete? (y/n/c) " yn
    case $yn in
        y ) rm -Rf /tmp/modelmesh-serving;
            git clone git@github.com:kserve/modelmesh-serving.git;
            cd modelmesh-serving || exit;
            MM_CONFIG="./config/default/config-defaults.yaml";
        yq -Y '.modelMeshImage = {"name": "quay.io/ruimvieira/modelmesh-test", "tag": "0.0.1"}' < ${MM_CONFIG} > tmp-config.yaml && mv tmp-config.yaml ${MM_CONFIG};;
        c ) echo "continuing...";;
        n ) echo "exiting...";
        exit;;
        * ) echo "invalid response";
        exit 1;;
    esac
fi

echo "Starting cluster"

kind create cluster --image=kindest/node:v1.22.15 --config "$ROOT"/kind/config.yaml

kubectl cluster-info --context kind-kind

kubectl create namespace modelmesh-serving

cd /tmp/modelmesh-serving || exit;
./scripts/install.sh --namespace-scope-mode --namespace modelmesh-serving --quickstart

kubectl apply -f "$ROOT"/k8s/model.yaml

echo "Deploy TrustyAI service"
kubectl apply -f "$ROOT"/k8s/storage.yaml -n modelmesh-serving
kubectl apply -f "$ROOT"/k8s/trustyai-configmap.yaml -n modelmesh-serving
kubectl apply -f "$ROOT"/k8s/trustyai-deployment.yaml -n modelmesh-serving

echo "Deploying the mlserver and model. This might take around 5 minutes."
while [[ $(kubectl get deployment modelmesh-serving-mlserver-0.x -n modelmesh-serving -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do echo "Waiting for model to deploy..." && sleep 20; done

sleep 10

echo "Forwarding ports"
kubectl port-forward --address 0.0.0.0 service/modelmesh-serving 8008 -n modelmesh-serving &
kubectl port-forward --address 0.0.0.0 service/modelmesh-serving 8033 -n modelmesh-serving &

echo "Ready to accept requests!"