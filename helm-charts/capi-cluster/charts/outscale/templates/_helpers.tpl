{{/*
Define Loadbalancer name : outscale limitation is max length 32
 default: if no loadbalancername is specified, generate 32 max length loadbalancername from trunc(28, sha256(cluster name))"-k8s"
*/}}

{{- define "outscale.defaultLoadbalancerName" -}}
{{- $loadbalancername := printf "%s-%s" (lower "{{ .Values.global.clusterName }}" | sha256sum | trunc 28 ) "k8s" }}
{{- if and (hasKey .Values "loadbalancername") (not (empty .Values.loadbalancername)) }}
{{- $loadbalancername = .Values.loadbalancername }}
{{- end }}
{{- $loadbalancername }}
{{- end }}

