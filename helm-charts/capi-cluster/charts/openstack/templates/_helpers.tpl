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

{{/*
vCPU and RAM in MiB of an openstack (Nubo) flavor, format: <FAMILY>.<vCPU>
RAM is proportional to the vCPU count within a family (RAM per vCPU):
  TI1  512MiB
  EQ1  1GiB
  CO1  2GiB
  TR1  3GiB
  UG1  4GiB
  MO1  8GiB
Returns nothing if the flavor does not follow this format or its family is unknown.

Usage: {{ include "openstack.flavorResources" "CO1.4" | fromYaml }}
Result:
  cpu: 4
  ram: 8192
*/}}
{{- define "openstack.flavorResources" -}}
{{- $ramPerCpuMiB := dict "TI1" 512 "EQ1" 1024 "CO1" 2048 "TR1" 3072 "UG1" 4096 "MO1" 8192 -}}
{{- $pattern := `^([A-Z]+[0-9]+)\.([0-9]+)$` -}}
{{- $flavor := toString . -}}
{{- if regexMatch $pattern $flavor -}}
{{- $family := regexReplaceAll $pattern $flavor "${1}" -}}
{{- $cpu := regexReplaceAll $pattern $flavor "${2}" | int -}}
{{- if hasKey $ramPerCpuMiB $family -}}
cpu: {{ $cpu }}
ram: {{ mul $cpu (get $ramPerCpuMiB $family) }}
{{- end -}}
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

Example: include "openstack.reservedMemoryMiB" (dict "memoryMiB" 8192 "maxPods" 110) → 1800
*/}}
{{- define "openstack.reservedMemoryMiB" -}}
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

Example: include "openstack.reservedCpuMillicores" (dict "cpu" 2) → 70
*/}}
{{- define "openstack.reservedCpuMillicores" -}}
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
of its flavor split between kubeReserved (2/3) and systemReserved (1/3):
  - enableCpu: cpu from openstack.reservedCpuMillicores
  - enableMemory: memory from openstack.reservedMemoryMiB

Usage: {{ include "openstack.kubeletConfiguration" (dict "root" $ "flavor" "CO1.4" "enableCpu" true "enableMemory" true) }}
*/}}
{{- define "openstack.kubeletConfiguration" -}}
{{- $config := tpl (toYaml .root.Values.global.KubeletConfiguration) .root | fromYaml -}}
{{- $vm := include "openstack.flavorResources" .flavor | fromYaml -}}
{{- if and (or .enableCpu .enableMemory) (not $vm) -}}
  {{- fail (printf "openstack.kubeletConfiguration: kubeletDynamicReservation requires a flavor following the format <FAMILY>.<vCPU> with FAMILY in TI1, EQ1, CO1, TR1, UG1, MO1, got %q" (toString .flavor)) -}}
{{- end -}}
{{- if .enableCpu -}}
  {{- $reserved := include "openstack.reservedCpuMillicores" (dict "cpu" $vm.cpu) | int -}}
  {{- $kubeReserved := div (mul $reserved 2) 3 -}}
  {{- $config = mergeOverwrite $config (dict
        "kubeReserved" (dict "cpu" (printf "%dm" $kubeReserved))
        "systemReserved" (dict "cpu" (printf "%dm" (sub $reserved $kubeReserved)))
      ) -}}
{{- end -}}
{{- if .enableMemory -}}
  {{- $reserved := include "openstack.reservedMemoryMiB" (dict "memoryMiB" $vm.ram "maxPods" ($config.maxPods | default 110)) | int -}}
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
