{{/*
Define Loadbalancer name : outscale limitation is max length 32
 default: if no loadbalancername is specified, generate 32 max length loadbalancername from trunc(28, sha256(cluster name))"-k8s"
*/}}
{{/*
  helm.subnet-list
  Returns a JSON array of 9 subnet CIDRs carved from a given network CIDR.

  Usage:
    {{ include "helm.subnet-list" "10.0.0.0/16" }}

  Constraints:
    - Base prefix must be between /16 and /24 (subnets will be /prefix+4)
    - 9 × blockSize must fit within the parent network
*/}}
{{- define "helm.subnet-list" -}}
  {{- $parts  := splitList "/" . -}}
  {{- $ip     := index $parts 0 -}}
  {{- $prefix := index $parts 1 | int -}}

  {{- $octets := splitList "." $ip -}}
  {{- $o1     := index $octets 0 | int -}}
  {{- $o2     := index $octets 1 | int -}}
  {{- $o3     := index $octets 2 | int -}}
  {{- $o4     := index $octets 3 | int -}}

  {{- $subPrefix := add $prefix 4 -}}

  {{/* Block sizes keyed by subnet prefix: 2^(32-subPrefix) */}}
  {{- $blockSizes := dict
      "16" 65536
      "17" 32768
      "18" 16384
      "19" 8192
      "20" 4096
      "21" 2048
      "22" 1024
      "23" 512
      "24" 256
      "25" 128
      "26" 64
      "27" 32
      "28" 16
  -}}

  {{- $blockSize := index $blockSizes (toString $subPrefix) -}}
  {{- if not $blockSize -}}
    {{- fail (printf "helm.subnet-list: unsupported prefix /%d (subnet prefix /%d). Base prefix must be between /16 and /24." $prefix $subPrefix) -}}
  {{- end -}}
  {{- $blockSize = int $blockSize -}}

  {{- $subnets := list -}}
  {{- range $i := until 9 -}}
    {{- $offset := mul $blockSize $i -}}
    {{- $newO2  := add $o2 (mod (div $offset 65536) 256) -}}
    {{- $newO3  := add $o3 (mod (div $offset 256) 256) -}}
    {{- $newO4  := add $o4 (mod $offset 256) -}}
    {{- $subnet := printf "%d.%d.%d.%d/%d" $o1 $newO2 $newO3 $newO4 $subPrefix -}}
    {{- $subnets = append $subnets $subnet -}}
  {{- end -}}

  {{- toJson $subnets -}}
{{- end -}}

{{- define "outscale.defaultLoadbalancerName" -}}
{{- $loadbalancername := printf "%s-%s" (lower .Values.global.clusterName | sha256sum | trunc 28 ) "k8s" }}
{{- if and (hasKey .Values "loadbalancername") (not (empty .Values.loadbalancername)) }}
{{- $loadbalancername = .Values.loadbalancername }}
{{- end }}
{{- $loadbalancername }}
{{- end }}

{{- define "outscale.validate" }}
{{- if .Values.multiaz }}
  {{- if not .Values.region }}
    {{- fail "Defining a region is required when multiaz is true" }}
  {{- end }}
  {{- if lt (int .Values.controlplane.replicas) 3 }}
    {{- fail "When using multiaz, you must have at lease 3 replicas for the controlplane" }}
  {{- end }}
{{- else }}
  {{- if not .Values.subregionName }}
    {{- fail "Defining subregionName is required when multiaz is false" }}
  {{- end }}
{{- end }}
{{- end }}

{{- define "outscale.subregionsLabels" }}
- a
{{- if .multiaz }}
- b
- c
{{- end }}
{{- end }}

{{/*
Function to compute number of replicas for a given subnet AZ. Given
the overall replicas for the nodepool and if we are using multiAZ or not.
Takes a dict as argument such as
{
    subregion: "a",
    replicas: 5,
    multiaz: true
}
Returns:
2
*/}}
{{- define "outscale.computeReplicas" }}
{{- $currentSubRegion := .subregion }}
{{- $totalReplicas := .replicas }}
{{- $multiaz := .multiaz }}
{{- $replicaDivider := 1 }}
{{- if $multiaz }}
{{- $replicaDivider = 3 }}
{{- end }}
{{- $orphanReplicas := mod $totalReplicas $replicaDivider }}
{{- $baseReplicas := div $totalReplicas $replicaDivider }}
{{- if (eq $orphanReplicas 0) }}
{{- $baseReplicas }}
{{- else if (eq $currentSubRegion "a") }}
{{- add1 $baseReplicas }}
{{- else if (and (gt $orphanReplicas 1) (eq $currentSubRegion "b")) }}
{{- add1 $baseReplicas }}
{{- else }}
{{- $baseReplicas }}
{{- end }}
{{- end }}

{{/*
Produce default tags for controlplane nodes
Returns a dict:
  tags.osc.fcu.repulse_server: xxx-{{ .Values.global.clusterName }}
*/}}
{{- define "outscale.kcpDefaultTags" -}}
{{- $tags := dict }}
{{- $tags = set $tags "tags.osc.fcu.repulse_server" (printf "kcp-%s" .Values.global.clusterName) }}
{{- $tags | toYaml }}
{{- end }}

{{/*
Produce default tags for worker nodes
Returns a dict:
  tags.osc.fcu.repulse_server: xxx-{{ .Values.global.clusterName }}-poolName
*/}}
{{- define "outscale.kwDefaultTags" -}}
{{ $ctx := .ctx }}
{{ $poolName := .name }}
{{- $tags := dict }}
{{- $tags = set $tags "tags.osc.fcu.repulse_server" (printf "kw-%s-%s" $ctx.global.clusterName $poolName) }}
{{- $tags | toYaml }}
{{- end }}

{{/*
Slugify an IP range
Usage: {{ include "outscale.IpSlugify" "1.1.1.1/32" }}
Result: "1-1-1-1-32"
*/}}
{{- define "outscale.IpSlugify" -}}
{{ . | replace "/" "-"  | replace "." "-" | trimSuffix "-" | trimPrefix "-" -}}
{{- end }}


{{/*
uniq name max 63 carac) for worker or controlplane node
based on:
- clusterName
- nodeType (worker | cp)
- poolName (if worker)
- kubeVersion
- imageId

Format :
  - Worker:     <cluster>-<clusterHash>-<poolHash>-<imgKubeHash>
  - ControlPlane: <cluster>-<clusterHash>-cp-<imgKubeHash>

Usage :
  {{ include "outscale.generatedName" (dict "clusterName" .Values.global.clusterName "nodeType" "worker" "poolName" $pool.name "kubeVersion" $pool.version "imageId" $pool.image) }}
*/}}
{{- define "outscale.generatedName" -}}

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

{{- /* last: Generation of the final name */ -}}
{{- $maxClusterLen := sub 63 (add (int (len $clusterHash)) (int (len $poolId)) (int (len $imageKubeHash)) 3) -}}
{{- $cluster := .clusterName | trunc (int $maxClusterLen) | trimSuffix "-" -}}

{{- printf "%s-%s-%s-%s" $cluster $clusterHash $poolId $imageKubeHash | toYaml -}}
{{- end }}
