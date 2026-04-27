{{- define "postgresql.fullname" -}}
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

{{- define "postgresql.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "postgresql.secretName" -}}
{{- if .Values.auth.existingSecret -}}
{{- .Values.auth.existingSecret -}}
{{- else -}}
{{- include "postgresql.fullname" . -}}
{{- end -}}
{{- end -}}

{{- define "postgresql.configMapName" -}}
{{- if .Values.configMap.nameOverride -}}
{{- .Values.configMap.nameOverride -}}
{{- else -}}
{{- printf "%s-config" (include "postgresql.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "postgresql.backup.fullname" -}}
{{- printf "%s-backup" (include "postgresql.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "postgresql.imagePullSecretName" -}}
{{- if .Values.imagePullSecret.name -}}
{{- .Values.imagePullSecret.name -}}
{{- else -}}
{{- printf "%s-pull-secret" (include "postgresql.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "postgresql.imagePullSecretsBlock" -}}
{{- $list := default (list) .Values.imagePullSecrets -}}
{{- if (default (dict) .Values.imagePullSecret).create -}}
{{- $list = append $list (dict "name" (include "postgresql.imagePullSecretName" .)) -}}
{{- end -}}
{{- if $list -}}
imagePullSecrets:
{{ toYaml $list | indent 2 }}
{{- end -}}
{{- end -}}

{{- define "postgresql.imageTag" -}}
{{- default .Chart.AppVersion .Values.image.tag -}}
{{- end -}}

{{- define "postgresql.backup.image" -}}
{{- $repo := default .Values.image.repository .Values.backup.image.repository -}}
{{- $tag  := default (include "postgresql.imageTag" .) .Values.backup.image.tag -}}
{{- printf "%s:%s" $repo $tag -}}
{{- end -}}

{{- define "postgresql.backup.imagePullPolicy" -}}
{{- default .Values.image.pullPolicy .Values.backup.image.pullPolicy -}}
{{- end -}}

{{- define "postgresql.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/name: {{ include "postgresql.name" . }}
app.kubernetes.io/part-of: postgresql
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{- define "postgresql.selectorLabels" -}}
app.kubernetes.io/name: {{ include "postgresql.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: postgresql
{{- end -}}

{{- define "postgresql.annotations" -}}
{{- $top := .top -}}
{{- $extra := default dict .extra -}}
{{- $merged := merge (deepCopy $extra) (deepCopy (default dict $top.Values.commonAnnotations)) -}}
{{- if $merged -}}
{{ toYaml $merged }}
{{- end -}}
{{- end -}}
