# cluster-api helm chart

Helm charts to manages the lifecycle of a Kubernetes clusters on different cloud using Cluster API.

Currently, the following charts are available:
| Chart | Description |
| --- | --- |
| [capi-cluster-addons](./capi-cluster-addons) | Deploys addons into a Kubernetes cluster, e.g. CCM, CNI, CSI. |
| [capi-cluster](./capi-cluster) | Deploys a Kubernetes cluster on a cloud. (Openstack,Outscale...) |

Currently the capi-cluster chart install:
- workload target cluster on Openstack cloud
- workload target cluster on Outscale cloud

In addition, it is possible to install in each clusters, additional components (addons) in the form of helm charts such as CNI, CCM, CSI ..

Addons are managed using custom resources provided by Cluster API Addon Provider. 

the following are required for a functional cluster: CCM, CNI

Providers:
  - openstack
  - outscale

Helmchartproxy addons:
  - ccm:
    - openstack-cloud-controller-manager
    - outscale: osc-cloud-controller-manager
  - cni:
    - cilium (include LB) - prefered
    - calico
  - csi:
    - openstack-cinder-csi
    - osc-bsu-csi-chart
  - metallb (with calico): LB for ingress
  - ingress-nginx
  - cert-manager
  - local-path-provisioner (use helm index in this repo from rancher)

## directory structures

```
capi-cluster/
  - charts/openstack
  - charts/openstac/ClusterResourceSet is used to deploy calico, cilium or secrets config
capi-cluster-addons/: helm charts for all addons (CNI,CCM...)
repo: helm repo index (make index to generate , don t forget to commit index and tgz file)
```

## Use it

```
# create config for your cluster for example: samples/c1-dev.yaml
# Adapt and modify to your needs (image, network, replica, credentials...)

export CLUSTER_NAME=c1-dev
cat samples/c1-demo.yaml.sample > samples/${CLUSTER_NAME}.yaml
cat samples/cluster-addons.yaml.sample > samples/cluster-addons.yaml

# install helm addons
helm upgrade --install -f samples/cluster-addons.yaml helm-addons ./capi-cluster-addons  --wait

# install workload cluster
helm upgrade --install -f samples/${CLUSTER_NAME}.yaml ${CLUSTER_NAME} ./capi-cluster  --wait

## Cluster is creating, check events !!

# get cluster kubeconfig
clusterctl get kubeconfig ${CLUSTER_NAME} > ${CLUSTER_NAME}.kubeconfig

# get pod
kubectl --kubeconfig=${CLUSTER_NAME}.kubeconfig get pod -A

# uninstall cluster
helm uninstall ${CLUSTER_NAME} --wait
```


## Tips and tricks

```
# On mgmt cluster
kubectl get cluster -A

# see clusterresourceset
kubectl get ClusterResourceSet -A
kubectl get configmap -A
kubectl get secrets -A

# On workload cluster, verify metallb config is deployed
kubectl --kubeconfig=${CLUSTER_NAME}.kubeconfig get L2Advertisement,ipaddresspool -A
```
