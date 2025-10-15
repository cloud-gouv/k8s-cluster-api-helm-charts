{{/*
unique name (max 63 chars) for worker or controlplane nodes
based on:
- clusterName
- nodeType (worker | cp)
- poolName (if worker)
- kubeVersion
- imageId

Format :
  - Worker:       <cluster>-<clusterHash>-<poolHash>-<imgKubeHash>
  - ControlPlane: <cluster>-<clusterHash>-cp-<imgKubeHash>

Usage :
  {{ include "openstack.generatedName" (dict "clusterName" .Values.global.clusterName "nodeType" "worker" "poolName" $name "kubeVersion" $pool.version "imageId" $pool.image) }}
*/}}
{{- define "openstack.generatedName" -}}

{{- /* Common initialization */ -}}
{{- $type := .nodeType | default "worker" -}}
{{- $imageId := .imageId | default "img" -}}
{{- $kubeVersion := .kubeVersion | default "v1" -}}
{{- $imageKubeHash := sha256sum (printf "%s-%s" $imageId $kubeVersion) | trunc 8 -}}
{{- $clusterHash := sha256sum .clusterName | trunc 8 -}}

{{- $poolId := "cp" -}}
{{- if eq $type "worker" -}}
  {{- $pool := .poolName | default "pool" -}}
  {{- $poolId = sha256sum $pool | trunc 8 -}}
{{- end -}}

{{- /* Final step: Generate the complete name */ -}}
{{- $maxClusterLen := sub 63 (add (int (len $clusterHash)) (int (len $poolId)) (int (len $imageKubeHash)) 3) -}}
{{- $cluster := .clusterName | trunc (int $maxClusterLen) | trimSuffix "-" -}}

{{- printf "%s-%s-%s-%s" $cluster $clusterHash $poolId $imageKubeHash | toYaml -}}
{{- end }}
