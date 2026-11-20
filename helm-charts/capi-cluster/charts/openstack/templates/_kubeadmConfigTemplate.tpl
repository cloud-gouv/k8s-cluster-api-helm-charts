{{/*
Spec of the KubeadmConfigTemplate of a worker pool.

Usage: {{ include "openstack.kubeadmConfigTemplateSpec" (dict "root" $ "name" $name "pool" $pool) }}
*/}}
{{- define "openstack.kubeadmConfigTemplateSpec" -}}
{{- $root := .root }}
{{- $pool := .pool -}}
spec:
  template:
    spec:
      {{- if $pool.additionalBlockDevices }}
      ##  Add external volume
      diskSetup:
         partitions:
         - device: /dev/vdb
           layout: true
           overwrite: false
           tableType: gpt
         filesystems:
         - device: /dev/vdb
           extraOpts:
           - -E
           - lazy_itable_init=1,lazy_journal_init=1
           filesystem: ext4
           label: {{ $pool.additionalBlockDevices.name }}_disk
      mounts:
        - - LABEL={{ $pool.additionalBlockDevices.name }}_disk
          - /mnt/disk
      {{- end }}
      {{- if hasKey $root.Values.global.kubeadmConfigSpec "verbosity" }}
      verbosity: {{ $root.Values.global.kubeadmConfigSpec.verbosity | default 1 }}
      {{- end }}
      joinConfiguration:
        nodeRegistration:
          imagePullPolicy: IfNotPresent
          name: {{`"{{ local_hostname }}"`}}
          kubeletExtraArgs:
            {{- with $pool.nodeLabels }}
            - name: node-labels
              value: "{{ range $i, $k := (keys . | sortAlpha) }}{{ if ne $i 0 }},{{ end }}{{ $k }}={{ index $pool.nodeLabels $k }}{{ end }}"
            {{- end }}
            - name: provider-id
              value: {{`"openstack:///{{ instance_id }}"`}}
          {{- with $pool.taints }}
          taints:
            {{- toYaml . | nindent 12 }}
          {{- end }}
        #
        # Here we specify the directory that contains the patch files
        # See: https://cluster-api.sigs.k8s.io/tasks/bootstrap/kubeadm-bootstrap/kubelet-config#use-kubeadms-kubeletconfiguration-patch-target
        # See: https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/control-plane-flags/#patches
        #
        patches:
          directory: /etc/kubernetes/patches
      preKubeadmCommands:
        - echo debug-pre > /tmp/out
        - mkdir -p /etc/pre-kubeadm-commands
        - for script in $(find /etc/pre-kubeadm-commands/ -name '*.sh' -type f | sort);
          do echo "Running script $script"; "$script"; done
      postKubeadmCommands:
        - echo debug-post >> /tmp/out
        - mkdir -p /etc/post-kubeadm-commands
        - for script in $(find /etc/post-kubeadm-commands/ -name '*.sh' -type f | sort);
          do echo "Running script $script"; "$script"; done
      files:
        # Here we put a patch file for kubeletconfiguration target in strategic patchtype on nodes via KubeadmConfigSpec.files
        # The naming convention of the patch file is kubeletconfiguration{suffix}+{patchtype}.yaml where {suffix} is an string and {patchtype} is one of the following: strategic, merge, json.
        # {suffix} determines the order of the patch files. The patches are applied in the alpha-numerical order of the {suffix}.
        #
        # See https://kubernetes.io/docs/reference/config-api/kubelet-config.v1beta1/
        #
        - path: /etc/kubernetes/patches/kubeletconfiguration0+strategic.yaml
          owner: "root:root"
          permissions: "0644"
          content: |
            apiVersion: kubelet.config.k8s.io/v1beta1
            kind: KubeletConfiguration
            {{- include "openstack.kubeletConfiguration" (dict
                  "root" $root
                  "flavor" $pool.flavor
                  "enableCpu" (dig "kubeletDynamicReservation" "cpu" false $pool)
                  "enableMemory" (dig "kubeletDynamicReservation" "memory" false $pool)
                ) | nindent 12 }}
        - path: /etc/pre-kubeadm-commands/10-containerd-restart.sh
          owner: root:root
          permissions: "0700"
          content: |
            #!/bin/bash
            #
            # pre-kubadm-scripts
            #
            set -e
            # apply containerd config before kubeadm
            systemctl daemon-reload
            systemctl restart containerd
        - path: /etc/apt/apt.conf.d/99proxy
          owner: "root:root"
          permissions: "0644"
          content: |
            Acquire {
              {{- if $root.Values.global.http_proxy }}
              http::Proxy {{ $root.Values.global.http_proxy | quote }};
              {{- end }}
              {{- if $root.Values.global.https_proxy }}
              https::Proxy {{ $root.Values.global.https_proxy | quote }};
              {{- end }}
              }
        - path: /etc/systemd/system/containerd.service.d/http-proxy.conf
          owner: "root:root"
          permissions: "0644"
          content: |
            [Service]
            {{- if $root.Values.global.http_proxy }}
            Environment="HTTP_PROXY={{ $root.Values.global.http_proxy }}"
            {{- end }}
            {{- if $root.Values.global.https_proxy }}
            Environment="HTTPS_PROXY={{ $root.Values.global.https_proxy }}"
            {{- end }}
            {{- if $root.Values.global.no_proxy }}
            Environment="NO_PROXY=.svc,.svc.cluster,.svc.cluster.local,127.0.0.0/8,192.168.0.0/16,{{ $root.Values.global.pods.cidrBlocks }},{{ $root.Values.global.services.cidrBlocks }}"
            {{- end }}
{{- end }}

{{/*
Name of the KubeadmConfigTemplate of a worker pool: <cluster>-<pool>-<specHash>

Usage: {{ include "openstack.kubeadmConfigTemplateName" (dict "root" $ "name" $name "pool" $pool) }}
*/}}
{{- define "openstack.kubeadmConfigTemplateName" -}}
{{- $spec := include "openstack.kubeadmConfigTemplateSpec" . -}}
{{- printf "%s-%s-%s" .root.Values.global.clusterName .name (sha256sum $spec | trunc 8) -}}
{{- end }}
