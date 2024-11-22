# cluster-api helm chart

Helm charts to manages the lifecycle of a Kubernetes clusters on different cloud using Cluster API.

Currently, the following charts are available:
| Chart | Description |
| --- | --- |
| [capi-cluster-addons](./helm-charts/capi-cluster-addons) | Deploys helm addons into a Kubernetes cluster, e.g. CCM, CNI, CSI. |
| [capi-cluster](./helm-charts/capi-cluster) | Deploys a Kubernetes cluster on a cloud. (Openstack,Outscale...) |

Currently the capi-cluster chart support:
- workload target cluster on Openstack cloud
- workload target cluster on Outscale cloud
