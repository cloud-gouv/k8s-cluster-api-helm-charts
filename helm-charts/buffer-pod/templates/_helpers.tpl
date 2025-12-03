{{- define "buffer-pod.fullname" -}}
{{- default .Chart.Name .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{- define "buffer-pod.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{- define "buffer-pod.labels" -}}
app.kubernetes.io/name: {{ include "buffer-pod.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "buffer-pod.selectorLabels" -}}
app.kubernetes.io/name: {{ include "buffer-pod.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
