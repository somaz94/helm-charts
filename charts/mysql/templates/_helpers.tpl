{{/*
Chart name used to derive resource names and as the label value.
Defaults to the Helm release name; overridable via .Values.fullnameOverride
or .Values.nameOverride.
*/}}
{{- define "mysql.fullname" -}}
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

{{- define "mysql.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Secret name. When auth.existingSecret is set, the chart skips Secret rendering
and resource references resolve to that name instead.
*/}}
{{- define "mysql.secretName" -}}
{{- if .Values.auth.existingSecret -}}
{{- .Values.auth.existingSecret -}}
{{- else -}}
{{- include "mysql.fullname" . -}}
{{- end -}}
{{- end -}}

{{/*
ConfigMap name. Defaults to `<fullname>-config`. Override with
`configMap.nameOverride` to adopt a legacy ConfigMap whose suffix differs
(e.g. `<fullname>` without `-config`).
*/}}
{{- define "mysql.configMapName" -}}
{{- if .Values.configMap.nameOverride -}}
{{- .Values.configMap.nameOverride -}}
{{- else -}}
{{- printf "%s-config" (include "mysql.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "mysql.backup.fullname" -}}
{{- printf "%s-backup" (include "mysql.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Pull Secret name. Default `<fullname>-pull-secret`; override with
`imagePullSecret.name`. Only consulted when `imagePullSecret.create` is true.
*/}}
{{- define "mysql.imagePullSecretName" -}}
{{- if .Values.imagePullSecret.name -}}
{{- .Values.imagePullSecret.name -}}
{{- else -}}
{{- printf "%s-pull-secret" (include "mysql.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/*
Render the `imagePullSecrets:` block for a Pod spec. Combines two sources:
  1. `.Values.imagePullSecrets`           — bring-your-own pull Secrets (BYOIPS).
  2. `<fullname>-pull-secret`             — chart-managed Secret rendered when
                                            `.Values.imagePullSecret.create` is true.
Outputs nothing when both lists are empty so the caller can `nindent` safely.
Usage: `{{- include "mysql.imagePullSecretsBlock" . | nindent 6 }}`
*/}}
{{- define "mysql.imagePullSecretsBlock" -}}
{{- $list := default (list) .Values.imagePullSecrets -}}
{{- if (default (dict) .Values.imagePullSecret).create -}}
{{- $list = append $list (dict "name" (include "mysql.imagePullSecretName" .)) -}}
{{- end -}}
{{- if $list -}}
imagePullSecrets:
{{ toYaml $list | indent 2 }}
{{- end -}}
{{- end -}}

{{/*
Resolved image tag — defaults to .Chart.AppVersion when .Values.image.tag is empty.
*/}}
{{- define "mysql.imageTag" -}}
{{- default .Chart.AppVersion .Values.image.tag -}}
{{- end -}}

{{/*
Backup image — falls back to the primary image when backup.image.* is empty.
*/}}
{{- define "mysql.backup.image" -}}
{{- $repo := default .Values.image.repository .Values.backup.image.repository -}}
{{- $tag  := default (include "mysql.imageTag" .) .Values.backup.image.tag -}}
{{- printf "%s:%s" $repo $tag -}}
{{- end -}}

{{- define "mysql.backup.imagePullPolicy" -}}
{{- default .Values.image.pullPolicy .Values.backup.image.pullPolicy -}}
{{- end -}}

{{/*
Common labels applied to every resource in this chart.
Caller may extend via .Values.commonLabels.
*/}}
{{- define "mysql.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/name: {{ include "mysql.name" . }}
app.kubernetes.io/part-of: mysql
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{/*
Selector labels — stable subset used in Deployment/Service selectors. Must NOT
include version/chart labels so pods survive chart version bumps.
*/}}
{{- define "mysql.selectorLabels" -}}
app.kubernetes.io/name: {{ include "mysql.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: mysql
{{- end -}}

{{/*
Per-resource annotations: merge of commonAnnotations and per-resource extra.
Usage: include "mysql.annotations" (dict "top" $top "extra" .Values.resourceMetadata.service.annotations)
Returns empty when both are empty (caller should guard with `if`).
*/}}
{{- define "mysql.annotations" -}}
{{- $top := .top -}}
{{- $extra := default dict .extra -}}
{{- $merged := merge (deepCopy $extra) (deepCopy (default dict $top.Values.commonAnnotations)) -}}
{{- if $merged -}}
{{ toYaml $merged }}
{{- end -}}
{{- end -}}
