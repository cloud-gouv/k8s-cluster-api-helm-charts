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
{{- if .multiaz }}
- a
- b
- c
{{- else }}
{{- printf "- %s" (.subregionName | splitList "" | last)}}
{{- end }}
{{- end }}

{{- define "outscale.region" }}
{{- if .multiaz }}
{{ .region }}
{{- else }}
{{- substr 0 (sub (len .subregionName) 1 | int) .subregionName}}
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

{{/*
vCPU and RAM in MiB of an outscale vmType, format: tinav<generation>.c<vCPU>r<RAM GiB>p<performance>
Returns nothing if the vmType does not follow this format.

Usage: {{ include "outscale.vmTypeResources" "tinav7.c2r8p2" | fromYaml }}
Result:
  cpu: 2
  ram: 8192
*/}}
{{- define "outscale.vmTypeResources" -}}
{{- $pattern := `^tinav[0-9]+\.c([0-9]+)r([0-9]+)p[0-9]+$` -}}
{{- $vmType := toString . -}}
{{- if regexMatch $pattern $vmType -}}
cpu: {{ regexReplaceAll $pattern $vmType "${1}" }}
ram: {{ mul (regexReplaceAll $pattern $vmType "${2}" | int) 1024 }}
{{- end -}}
{{- end }}

{{/*
Memory (MiB) to reserve on a node, rounded down to 100MiB.
Formula from GKE: https://docs.cloud.google.com/kubernetes-engine/docs/concepts/plan-node-sizes#memory_reservations

  reserved = min(tiers, 15MiB * maxPods + 700MiB)

tiers:
  < 1GiB       255MiB
  0-4GiB       25%
  4-8GiB       20%
  8-16GiB      10%
  16-128GiB     6%
  > 128GiB      2%

Example: include "outscale.reservedMemoryMiB" (dict "memoryMiB" 8192 "maxPods" 110) → 1800
*/}}
{{- define "outscale.reservedMemoryMiB" -}}
{{- $m := int .memoryMiB -}}
{{- $tiers := 255 -}}
{{- if ge $m 1024 -}}
  {{- /* Totals of full tiers, in MiB x percent (divided by 100 at the end) */ -}}
  {{- $full4G   := mul 4096 25 -}}                                  {{- /* 0-4GiB at 25%    = 102400 */ -}}
  {{- $full8G   := add $full4G   (mul (sub 8192 4096) 20) -}}       {{- /* + 4-8GiB at 20%  = 184320 */ -}}
  {{- $full16G  := add $full8G   (mul (sub 16384 8192) 10) -}}      {{- /* + 8-16GiB at 10% = 266240 */ -}}
  {{- $full128G := add $full16G  (mul (sub 131072 16384) 6) -}}     {{- /* + 16-128GiB at 6% = 954368 */ -}}

  {{- $weighted := 0 -}}
  {{- if le $m 4096 -}}
    {{- /* RAM within the first tier: 25% of all of it */ -}}
    {{- $weighted = mul $m 25 -}}
  {{- else if le $m 8192 -}}
    {{- /* first 4GiB full, plus 20% of what's above 4GiB */ -}}
    {{- $weighted = add $full4G (mul (sub $m 4096) 20) -}}
  {{- else if le $m 16384 -}}
    {{- /* first 8GiB full, plus 10% of what's above 8GiB */ -}}
    {{- $weighted = add $full8G (mul (sub $m 8192) 10) -}}
  {{- else if le $m 131072 -}}
    {{- /* first 16GiB full, plus 6% of what's above 16GiB */ -}}
    {{- $weighted = add $full16G (mul (sub $m 16384) 6) -}}
  {{- else -}}
    {{- /* first 128GiB full, plus 2% of what's above 128GiB */ -}}
    {{- $weighted = add $full128G (mul (sub $m 131072) 2) -}}
  {{- end -}}
  {{- $tiers = div $weighted 100 -}}
{{- end -}}
{{- $reserved := min $tiers (add (mul 15 (int .maxPods)) 700) -}}
{{- mul (div $reserved 100) 100 -}}
{{- end }}

{{/*
CPU (millicores) to reserve on a node, rounded down to 1m.
Formula from GKE: https://docs.cloud.google.com/kubernetes-engine/docs/concepts/plan-node-sizes#cpu_reservations

  reserved = min(tiers, 1000m)

tiers:
  first core       6%
  second core      1%
  cores 3-4        0.5%
  above 4 cores    0.25%

Example: include "outscale.reservedCpuMillicores" (dict "cpu" 2) → 70
*/}}
{{- define "outscale.reservedCpuMillicores" -}}
{{- $c := int .cpu -}}
{{- /* Totals in tenths of millicore, 0.25% of a core being 2.5m */ -}}
{{- $weighted := 0 -}}
{{- if le $c 1 -}}
  {{- $weighted = mul $c 600 -}}
{{- else if le $c 2 -}}
  {{- $weighted = add 600 (mul (sub $c 1) 100) -}}
{{- else if le $c 4 -}}
  {{- $weighted = add 700 (mul (sub $c 2) 50) -}}
{{- else -}}
  {{- $weighted = add 800 (mul (sub $c 4) 25) -}}
{{- end -}}
{{- min (div $weighted 10) 1000 -}}
{{- end }}

{{/*
KubeletConfiguration of a node, as yaml: global.KubeletConfiguration and the reservations
of its vmType split between kubeReserved (2/3) and systemReserved (1/3):
  - enableCpu: cpu from outscale.reservedCpuMillicores
  - enableMemory: memory from outscale.reservedMemoryMiB

Usage: {{ include "outscale.kubeletConfiguration" (dict "root" $ "vmType" "tinav7.c2r8p2" "enableCpu" true "enableMemory" true) }}
*/}}
{{- define "outscale.kubeletConfiguration" -}}
{{- $config := tpl (toYaml .root.Values.global.KubeletConfiguration) .root | fromYaml -}}
{{- $vm := include "outscale.vmTypeResources" .vmType | fromYaml -}}
{{- if and (or .enableCpu .enableMemory) (not $vm) -}}
  {{- fail (printf "outscale.kubeletConfiguration: kubeletDynamicReservation requires a vmType following the format tinav<generation>.c<vCPU>r<RAM GiB>p<performance>, got %q" (toString .vmType)) -}}
{{- end -}}
{{- if .enableCpu -}}
  {{- $reserved := include "outscale.reservedCpuMillicores" (dict "cpu" $vm.cpu) | int -}}
  {{- $kubeReserved := div (mul $reserved 2) 3 -}}
  {{- $config = mergeOverwrite $config (dict
        "kubeReserved" (dict "cpu" (printf "%dm" $kubeReserved))
        "systemReserved" (dict "cpu" (printf "%dm" (sub $reserved $kubeReserved)))
      ) -}}
{{- end -}}
{{- if .enableMemory -}}
  {{- $reserved := include "outscale.reservedMemoryMiB" (dict "memoryMiB" $vm.ram "maxPods" ($config.maxPods | default 110)) | int -}}
  {{- $kubeReserved := div (mul $reserved 2) 3 -}}
  {{- $config = mergeOverwrite $config (dict
        "kubeReserved" (dict "memory" (printf "%dMi" $kubeReserved))
        "systemReserved" (dict "memory" (printf "%dMi" (sub $reserved $kubeReserved)))
      ) -}}
{{- end -}}
{{- if $config -}}
{{- toYaml $config -}}
{{- end -}}
{{- end }}
