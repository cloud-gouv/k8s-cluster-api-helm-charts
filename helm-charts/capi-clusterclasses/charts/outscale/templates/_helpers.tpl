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
