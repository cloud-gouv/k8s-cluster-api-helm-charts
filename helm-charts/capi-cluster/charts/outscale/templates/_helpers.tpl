{{/*
Define Loadbalancer name : outscale limitation is max length 32
 default: if no loadbalancername is specified, generate 32 max length loadbalancername from trunc(28, sha256(cluster name))"-k8s"
*/}}

{{- define "outscale.defaultLoadbalancerName" -}}
{{- $loadbalancername := printf "%s-%s" (lower .Values.global.clusterName | sha256sum | trunc 28 ) "k8s" }}
{{- if and (hasKey .Values "loadbalancername") (not (empty .Values.loadbalancername)) }}
{{- $loadbalancername = .Values.loadbalancername }}
{{- end }}
{{- $loadbalancername }}
{{- end }}

{{- define "outscale.subregionsLabels" }}
- a
{{- if .multiaz }}
- b
- c
{{- end }}
{{- end }}

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
