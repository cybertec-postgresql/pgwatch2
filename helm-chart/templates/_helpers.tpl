{{/*
Expand the name of the chart.
*/}}
{{- define "pgwatch2.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "pgwatch2.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "pgwatch2.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "pgwatch2.grafana_major" -}}
v{{- substr 0 1 .Subcharts.grafana.Chart.AppVersion }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "pgwatch2.labels" -}}
helm.sh/chart: {{ include "pgwatch2.chart" . }}
{{ include "pgwatch2.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "pgwatch2.selectorLabels" -}}
app.kubernetes.io/name: {{ include "pgwatch2.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "webui.selectorLabels" -}}
app: {{ include "pgwatch2.name" . }}-webui
app.kubernetes.io/name: {{ include "pgwatch2.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "pgwatch2.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "pgwatch2.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}
