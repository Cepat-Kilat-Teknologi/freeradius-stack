{{/*
Expand the name of the chart.
*/}}
{{- define "freeradius.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "freeradius.fullname" -}}
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
{{- define "freeradius.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "freeradius.labels" -}}
helm.sh/chart: {{ include "freeradius.chart" . }}
{{ include "freeradius.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "freeradius.selectorLabels" -}}
app.kubernetes.io/name: {{ include "freeradius.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
MySQL labels
*/}}
{{- define "freeradius.mysql.labels" -}}
helm.sh/chart: {{ include "freeradius.chart" . }}
app.kubernetes.io/name: {{ include "freeradius.name" . }}-mysql
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: database
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
MySQL selector labels
*/}}
{{- define "freeradius.mysql.selectorLabels" -}}
app.kubernetes.io/name: {{ include "freeradius.name" . }}-mysql
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "freeradius.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "freeradius.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
MySQL host
*/}}
{{- define "freeradius.mysql.host" -}}
{{- if .Values.mysql.enabled }}
{{- printf "%s-mysql" (include "freeradius.fullname" .) }}
{{- else }}
{{- .Values.externalMysql.host }}
{{- end }}
{{- end }}

{{/*
MySQL port
*/}}
{{- define "freeradius.mysql.port" -}}
{{- if .Values.mysql.enabled }}
{{- "3306" }}
{{- else }}
{{- .Values.externalMysql.port | toString }}
{{- end }}
{{- end }}

{{/*
MySQL database
*/}}
{{- define "freeradius.mysql.database" -}}
{{- if .Values.mysql.enabled }}
{{- .Values.mysql.database }}
{{- else }}
{{- .Values.externalMysql.database }}
{{- end }}
{{- end }}

{{/*
MySQL user
*/}}
{{- define "freeradius.mysql.user" -}}
{{- if .Values.mysql.enabled }}
{{- .Values.mysql.user }}
{{- else }}
{{- .Values.externalMysql.user }}
{{- end }}
{{- end }}
