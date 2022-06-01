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

{{/*
Return the appropriate apiVersion for ingress.
*/}}
{{- define "pgwatch2.ingress.apiVersion" -}}
  {{- if and (.Capabilities.APIVersions.Has "networking.k8s.io/v1") (semverCompare ">= 1.19-0" .Capabilities.KubeVersion.Version) -}}
      {{- print "networking.k8s.io/v1" -}}
  {{- else if .Capabilities.APIVersions.Has "networking.k8s.io/v1beta1" -}}
    {{- print "networking.k8s.io/v1beta1" -}}
  {{- else -}}
    {{- print "extensions/v1beta1" -}}
  {{- end -}}
{{- end -}}

{{/*
Return if ingress is stable.
*/}}
{{- define "pgwatch2.ingress.isStable" -}}
  {{- eq (include "pgwatch2.ingress.apiVersion" .) "networking.k8s.io/v1" -}}
{{- end -}}

{{/*
Return if ingress supports ingressClassName.
*/}}
{{- define "pgwatch2.ingress.supportsIngressClassName" -}}
  {{- or (eq (include "pgwatch2.ingress.isStable" .) "true") (and (eq (include "pgwatch2.ingress.apiVersion" .) "networking.k8s.io/v1beta1") (semverCompare ">= 1.18-0" .Capabilities.KubeVersion.Version)) -}}
{{- end -}}

{{/*
Return if ingress supports pathType.
*/}}
{{- define "pgwatch2.ingress.supportsPathType" -}}
  {{- or (eq (include "pgwatch2.ingress.isStable" .) "true") (and (eq (include "pgwatch2.ingress.apiVersion" .) "networking.k8s.io/v1beta1") (semverCompare ">= 1.18-0" .Capabilities.KubeVersion.Version)) -}}
{{- end -}}

{{- define "pgwatch2-storage" -}}
{{- if eq .Values.storage "influx" -}}
influxdb
{{- else  -}}
{{- .Values.storage -}}
{{- end -}}
{{- end }}

