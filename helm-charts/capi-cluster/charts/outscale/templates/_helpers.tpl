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
