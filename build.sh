#!/bin/bash

export PROD_DIR=`dirname $0`
export Command_Usage="./build.sh -o [option]"

if kubectl get nodes > /dev/null 2>&1 ; then


#######################################
function Setup_Namespace() {
    if kubectl get ns ${1} > /dev/null 2>&1 ; then
        echo "namespace already created"
    else
        echo "creating namespace ${1}"
        kubectl create ns ${1}
    fi

    export K8S_NAMESPACE=${1}
    export namespace_options="--namespace=${K8S_NAMESPACE}"
}


#######################################
## Check Statefulset status
function Statefulset_Status_Wait() {
    echo "Checking Statefulset status on : ${namespace_options} for the Statefulset : ${1}"
    if kubectl ${namespace_options} get statefulsets | grep ${1} > /dev/null 2>&1 ; then
        STATEFUL_STATUS=""
        POD_STATUS=""
        REPLICA_NUMBER=$(kubectl ${namespace_options} get statefulsets redis-cluster -o jsonpath="{.spec.replicas}")
        while [ "${STATEFUL_STATUS}" != "${REPLICA_NUMBER}/${REPLICA_NUMBER}" ]; do
            echo "Waiting for ${1} statefulset deployment to be completed"
            sleep 1;
            if [[ ${POD_STATUS} == "Error" ]] ; then
                echo "pods ${1} Failed"
                exit 1
            fi
            STATEFUL_STATUS=$(kubectl ${namespace_options} get statefulsets | grep ${1} | awk '{print $2}')
            POD_STATUS=$(kubectl ${namespace_options} get pods --sort-by='{.metadata.creationTimestamp}' | grep ${1} | awk '{print $3}' | tail -1)
        done
        echo "statefulset deployment ${1} Completed Successfully"
    else
        echo "no statefulset deployment found with name : ${1}"
        exit 1
    fi
}


#######################################
# deploy redis cluster
function Redis_Deploy() {
    echo "Deploying redis cluster on k8s"
    Setup_Namespace redis
    kubectl ${namespace_options} apply -f ${PROD_DIR}/K8s-Infra/redis-configmap.yaml
    kubectl ${namespace_options} apply -f ${PROD_DIR}/K8s-Infra/redis-deployment.yaml
    kubectl ${namespace_options} apply -f ${PROD_DIR}/K8s-Infra/redis-service.yaml
    Statefulset_Status_Wait redis-cluster
    kubectl ${namespace_options} exec -it redis-cluster-0 -- redis-cli --cluster create --cluster-replicas 1 $(kubectl ${namespace_options} get pods -l app=redis-cluster -o jsonpath='{range.items[*]}{.status.podIP}:6379 ')
}


#######################################
# deploy application
function Counterapp_Deploy() {
    Setup_Namespace apps
    export DeploymentTime=$(date +%F--%H-%M-%S--%Z)
    if kubectl get pods ${namespace_options} | grep flask-counter-app >/dev/null ; then
        envsubst < ${PROD_DIR}/K8s-Infra/counter_app-deployment.yaml    |    kubectl ${namespace_options} replace -f -
    else
        envsubst < ${PROD_DIR}/K8s-Infra/counter_app-deployment.yaml   |    kubectl ${namespace_options} apply -f -
    fi
    kubectl ${namespace_options} apply -f ${PROD_DIR}/K8s-Infra/counter_app-service.yaml
}







while getopts ":o:" opt
   do
     case $opt in
        o ) option=$OPTARG;;
     esac
done


if [[ $option = redis ]]; then
	Redis_Deploy
elif [[ $option = counter_app ]]; then
	Counterapp_Deploy
elif [[ $option = full_deploy ]]; then
    Setup_Namespace create
    Redis_Deploy
	Counterapp_Deploy
else
	echo "$Command_Usage"
cat << EOF
_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_

Main modes of operation:

   redis            :       Deploy HA Redis on K8s
   counter_app      :       Deploy the application on K8s
   full_deploy      :       Complete Deployment and configuration in single command

_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_
EOF
fi


else
  echo "Not able to connect k8s...!"
  echo "task aborting.....!"
  exit 1
fi
