# flask-counter-app

## Prerequisite

* [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/)
* [helm](https://helm.sh/docs/intro/install/)
* envsubst


## Create your K8s Cluster on AWS

You can directly create the kubernetes cluster from aws web ui, but in this example we are creating it with `eksctl` command from terminal

[install / upgrade eksctl](https://docs.aws.amazon.com/eks/latest/userguide/eksctl.html)

```
eksctl create cluster \
    --name K8s-Cluster \
    --version 1.14 \
    --zones us-east-1a,us-east-1b,us-east-1c \
    --region us-east-1 \
    --nodegroup-name K8s-Cluster-Nodeworkers \
    --node-type t2.medium \
    --nodes 3 \
    --nodes-min 3 \
    --nodes-max 5 \
    --managed
```

Note : Its better to choose compute optimized machines like AWS `c5n.large`

**Update your kubeconfig file with the following command**

```
aws eks --region us-east-1 update-kubeconfig --name K8s-Cluster
```

## kubernetes Deployment for Redis Cluster

We are going to set up a 6 nodes cluster with 3 masters and 3 slaves. StatefullSet creates a group of individual Redis instances in cluster mode and each requests a persistent volume through a PersistentVolumeClaim ( automatically provisioned through the volumeClaimTemplate) and links with that dedicated volume.

NOTE: we use the built-in redis-cli tool for our health and readiness probes to make sure our pods are working as intended.


## Docker image for flask-counter-app

This demo configuring redis cluster in kubernetes having 6 nodes, so the docker image `tarunbhardwaj/flask-counter-app:latest` does't support the [redis cluster configuration](https://redis-py-cluster.readthedocs.io/en/master/). tomake it work, i forked the [tarunbhardwaj repository](https://github.com/tarunbhardwaj/flask-counter-app.git) and reconfigured the application to accept the redis cluster configuration. the latest docker image im using is ``akhilrajmailbox/flask-counter-app:latest``

The environment value will change as follow : 

```
Old value : REDIS_URL='redis://redis-host:6379/0'
New value : REDIS_URL='redis-host'
```

## Horizontal Pod Autoscaler

For Configuring HPA (Horizontal Pod Autoscaler) we are installing `Metrics Server` with help of `helm charts`. In this demo, We are using helm version < 3.x.x so the helm server configuration required and the `build.sh` script will take care of it.

For testing purpose, the autoscaling configuration is as follows :

```
CPU limit           :   50 %
Min Number of Pods  :   1
Max Number of Pods  :   20
```

**You can test your deployment via apache benchmark [ab](https://httpd.apache.org/docs/2.4/programs/ab.html)**

```
ab -l -c 100 -t 10 http://LOADBALANCER_IPADDRESS/
```

The above command will increase the cpu usage in the `counter app` and HPA will increase the number of pods for this  in order to serve all the request upto 10 (Max Number of Pods). when the cpu goes donw, then the number of pods become 1 (Min Number of Pods).

## Deployment

You can deploy the complete solution with help of a simple script.

```
git clone 
cd flask-counter-app
./build.sh -o full_deploy
```


Main modes of operation in `build.sh`:

```
   redis            :       Deploy HA Redis on K8s
   metrics_deploy   :       Configure and Deploy Metrics Server (for HPA)
   counter_app      :       Deploy the application on K8s
   full_deploy      :       Complete Deployment and configuration in single command
```