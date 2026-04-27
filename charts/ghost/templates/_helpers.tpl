{{/*
Chart name used to derive resource names and as the label value.
Defaults to the Helm release name; overridable via .Values.fullnameOverride
or .Values.nameOverride.
*/}}
{{- define "ghost.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "ghost.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
MySQL-specific names. Default: `<fullname>-mysql`. Override with
`mysql.fullnameOverride` to adopt pre-existing resources whose names do not
fit the default pattern (for example, when migrating off a legacy raw-YAML
deployment that named the MySQL Service `<release>-db`).
*/}}
{{- define "ghost.mysql.fullname" -}}
{{- if .Values.mysql.fullnameOverride -}}
{{- .Values.mysql.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-mysql" (include "ghost.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "ghost.mysql.secretName" -}}
{{- if .Values.mysql.auth.existingSecret -}}
{{- .Values.mysql.auth.existingSecret -}}
{{- else -}}
{{- include "ghost.mysql.fullname" . -}}
{{- end -}}
{{- end -}}

{{/*
ConfigMap name. Default: same as `ghost.mysql.fullname`. Override with
`mysql.configMap.nameOverride` when the legacy ConfigMap uses a different
suffix (e.g. `<mysql-fullname>-config`) so existing data can be adopted.
*/}}
{{- define "ghost.mysql.configMapName" -}}
{{- if .Values.mysql.configMap.nameOverride -}}
{{- .Values.mysql.configMap.nameOverride -}}
{{- else -}}
{{- include "ghost.mysql.fullname" . -}}
{{- end -}}
{{- end -}}

{{- define "ghost.backup.fullname" -}}
{{- printf "%s-backup" (include "ghost.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Resolved database host (service name when mysql.enabled, else externalDatabase.host).
*/}}
{{- define "ghost.databaseHost" -}}
{{- if .Values.mysql.enabled -}}
{{- include "ghost.mysql.fullname" . -}}
{{- else -}}
{{- .Values.externalDatabase.host -}}
{{- end -}}
{{- end -}}

{{- define "ghost.databasePort" -}}
{{- if .Values.mysql.enabled -}}
{{- .Values.mysql.service.port -}}
{{- else -}}
{{- .Values.externalDatabase.port | default 3306 -}}
{{- end -}}
{{- end -}}

{{- define "ghost.database.secretName" -}}
{{- if .Values.mysql.enabled -}}
{{- include "ghost.mysql.secretName" . -}}
{{- else if .Values.externalDatabase.existingSecret -}}
{{- .Values.externalDatabase.existingSecret -}}
{{- else -}}
{{- printf "%s-db" (include "ghost.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/*
Common labels applied to every resource in this chart.
Caller may extend via .Values.commonLabels.
*/}}
{{- define "ghost.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/name: {{ include "ghost.name" . }}
app.kubernetes.io/part-of: ghost
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{/*
Selector labels — stable subset used in Deployment/Service selectors. Must NOT
include version/chart labels so pods survive chart version bumps.
*/}}
{{- define "ghost.selectorLabels" -}}
app.kubernetes.io/name: {{ include "ghost.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: ghost
{{- end -}}

{{- define "ghost.mysql.selectorLabels" -}}
app.kubernetes.io/name: {{ include "ghost.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: mysql
{{- end -}}

{{/*
Per-resource annotations: merge of commonAnnotations and per-resource extra.
Usage: include "ghost.annotations" (dict "top" $top "extra" .Values.resourceMetadata.httproute.annotations)
Returns empty when both are empty (caller should guard with `if`).
*/}}
{{- define "ghost.annotations" -}}
{{- $top := .top -}}
{{- $extra := default dict .extra -}}
{{- $merged := merge (deepCopy $extra) (deepCopy (default dict $top.Values.commonAnnotations)) -}}
{{- if $merged -}}
{{ toYaml $merged }}
{{- end -}}
{{- end -}}
