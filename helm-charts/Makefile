HELM_VALUE = ""
CLUSTER_NAME = ""

LOCAL_PATH_VERSION = v0.0.30
OSC_CCM_VERSION = 0.3.0 0.3.1 0.3.2
OSC_CSI_VERSION = 1.6.0

index: package-capi-cluster \
       package-capi-cluster-addons \
       package-local-path-provisioner \
       package-osc-cloud-controller-manager \
       package-osc-bsu-csi-driver \
       index-repo
package-capi-cluster:
	helm package capi-cluster -d repo/
package-capi-cluster-addons:
	helm package capi-cluster-addons -d repo/

package-local-path-provisioner: $(LOCAL_PATH_VERSION)
$(LOCAL_PATH_VERSION):
	( rm -rf local-path-provisioner ; \
          git clone https://github.com/rancher/local-path-provisioner.git --depth 1 --branch $@ ; \
          helm package local-path-provisioner/deploy/chart/local-path-provisioner -d repo/ ; \
          rm -rf local-path-provisioner )
## for Dev only: to use own MR to the official cloud-provider-openstack
package-cloud-provider-openstack:
	( rm -rf cloud-provider-openstack ; \
          git clone https://github.com/pli01/cloud-provider-openstack --depth 1 --branch add-cinder-csi-helm-extra-env ; \
          # git clone https://github.com/kubernetes/cloud-provider-openstack --depth 1 --branch openstack-cinder-csi-2.30.1-alpha.1 ; \
          # helm package cloud-provider-openstack/charts/cinder-csi-plugin -d repo/ ; \
          # rm -rf cloud-provider-openstack )
	)

# dockerhub rate-limit: mirror here
package-osc-cloud-controller-manager: $(OSC_CCM_VERSION)
$(OSC_CCM_VERSION):
	cd repo && helm pull oci://registry-1.docker.io/outscalehelm/osc-cloud-controller-manager --version $@
package-osc-bsu-csi-driver: $(OSC_CSI_VERSION)
$(OSC_CSI_VERSION):
	cd repo && helm pull oci://registry-1.docker.io/outscalehelm/osc-bsu-csi-driver --version $@

index-repo:
	helm repo index repo/

SHELL := /bin/bash
check-template:
	[[ -n "${HELM_VALUE}" && -n "${CLUSTER_NAME}" ]] || exit 1
template-capi-cluster: check-template
	helm template -f ${HELM_VALUE} ${CLUSTER_NAME} capi-cluster
template-capi-cluster-addons: check-template
	helm template -f ${HELM_VALUE} ${CLUSTER_NAME} capi-cluster-addons
