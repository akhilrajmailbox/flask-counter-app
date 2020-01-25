#!/bin/bash
type kubectl >/dev/null 2>&1 || { echo >&2 "CRITICAL: The kubectl is required for this script to run"; exit 2; }
type helm >/dev/null 2>&1 || { echo >&2 "CRITICAL: The helm client is required for this script to run"; exit 2; }
type envsubst >/dev/null 2>&1 || { echo >&2 "CRITICAL: The envsubst utility is required for this script to run"; exit 2; }

export PROD_DIR=`dirname $0`
export Command_Usage="./build.sh -o [option]"

if kubectl get nodes > /dev/null 2>&1 ; then


#######################################
function Setup_Namespace() {
    if kubectl get ns ${1} > /dev/null 2>&1 ; then
        echo "namespace ${1} already created"
    else
        echo "creating namespace ${1}"
        kubectl create ns ${1}
    fi

    export K8S_NAMESPACE=${1}
    export namespace_options="--namespace=${K8S_NAMESPACE}"
}


#######################################
## Check pod status
function Pod_Status_Wait() {

    echo "Checking pod status on : ${namespace_options} for the pod : ${1}"
    Pod_Name=$(kubectl ${namespace_options} get pods ${1} | awk '{if(NR>1)print $1}')

    for i in ${Pod_Name} ; do
        Pod_Status=""
        until [[ ${Pod_Status} == "Running" ]] ; do
            echo "Waiting for the pod : ${i} to start...!"
            export Pod_Status=$(kubectl ${namespace_options} get pods ${i} -o jsonpath="{.status.phase}")
        done
        echo "The pod : ${i} started and running...!"
    done
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
    if kubectl get pods ${namespace_options} | grep flask-counter-app >/dev/null 2>&1 ; then
        envsubst < ${PROD_DIR}/K8s-Infra/counter_app-deployment.yaml    |    kubectl ${namespace_options} replace -f -
    else
        envsubst < ${PROD_DIR}/K8s-Infra/counter_app-deployment.yaml   |    kubectl ${namespace_options} apply -f -
    fi
    kubectl ${namespace_options} apply -f ${PROD_DIR}/K8s-Infra/counter_app-service.yaml
}


#######################################
# HPA for counter_app application
function hpa_config() {
    Setup_Namespace apps
    ## HPA configuration
    local cpu_percent=${1}
    local min_pod=${2}
    local max_pod=${3}
    echo "Deploying HORIZONTAL POD AUTOSCALER with --cpu-percent=${cpu_percent} --min=${min_pod} --max=${max_pod}"
    if kubectl ${namespace_options} get hpa flask-counter-app >/dev/null 2>&1 ; then
        kubectl ${namespace_options} delete hpa flask-counter-app
    fi
    kubectl ${namespace_options} autoscale deployment flask-counter-app --cpu-percent=${cpu_percent} --min=${min_pod} --max=${max_pod}
}


################################################
function helm_config() {
    # echo "installing helm in your system"
    # curl -L https://git.io/get_helm.sh | bash
    Setup_Namespace kube-system

    if helm version | grep "Client:" | grep 'SemVer:"v3.' ; then
        echo "Your helm version is 3 and doesn't required the server configuration...!"
    else
        if ! kubectl get  deploy --namespace kube-system tiller-deploy ; then
            echo "Your helm required the server configuration...!"
            kubectl create serviceaccount --namespace kube-system tiller
            kubectl create clusterrolebinding tiller-cluster-rule --clusterrole=cluster-admin --serviceaccount=kube-system:tiller
            helm init --service-account tiller
            echo "waiting for 10 sec"
            sleep 10
            # kubectl patch deploy --namespace kube-system tiller-deploy -p '{"spec":{"template":{"spec":{"serviceAccount":"tiller"}}}}'
            # helm init --service-account tiller --upgrade
            TILLER_POD=$(kubectl ${namespace_options} get pods -l "name=tiller" -o jsonpath="{.items[0].metadata.name}")
            Pod_Status_Wait ${TILLER_POD}
        fi
    fi
}


################################################
function metrics_deploy() {
    helm_config
    helm install stable/metrics-server \
        --name metrics-server \
        --version 2.0.4 \
        --namespace metrics

    SERVER_STATUS=$(kubectl get apiservice v1beta1.metrics.k8s.io -o jsonpath="{.status.conditions[0].status}")
    until [[ ${SERVER_STATUS} == "True" ]] ; do
        echo "waiting for metrics-server to start....!"
        SERVER_STATUS=$(kubectl get apiservice v1beta1.metrics.k8s.io -o jsonpath="{.status.conditions[0].status}")
    done
}


while getopts ":o:" opt
   do
     case $opt in
        o ) option=$OPTARG;;
     esac
done


if [[ $option = redis ]]; then
	Redis_Deploy
elif [[ $option = metrics_deploy ]]; then
    metrics_config
elif [[ $option = counter_app ]]; then
	Counterapp_Deploy
    hpa_config 50 1 20
elif [[ $option = full_deploy ]]; then
    metrics_deploy
    Redis_Deploy
	Counterapp_Deploy
    hpa_config 50 1 20
else
	echo -e "\n$Command_Usage\n"
cat << EOF
_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_

Main modes of operation:

   redis            :       Deploy HA Redis on K8s
   metrics_deploy   :       Configure and Deploy Metrics Server (for HPA)
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
