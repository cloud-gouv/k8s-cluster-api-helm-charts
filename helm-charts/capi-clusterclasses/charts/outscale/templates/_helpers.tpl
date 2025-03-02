{{/*
Set the name of the clusterclass
*/}}
{{- define "outscale.name" -}}
{{- printf "%s-%s" "outscale" (default (printf "v%s" .Chart.Version) .Values.forceClusterclassVersion) | trimSuffix "-" -}}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "outscale.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "outscale.labels" -}}
helm.sh/chart: {{ include "outscale.chart" . }}
{{ include "outscale.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "outscale.selectorLabels" -}}
app.kubernetes.io/name: {{ include "outscale.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

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
