{{- define "unity-mcp-server.fullname" -}}
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

{{- define "unity-mcp-server.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "unity-mcp-server.secretName" -}}
{{- if .Values.apiKey.existingSecret -}}
{{- .Values.apiKey.existingSecret -}}
{{- else -}}
{{- printf "%s-api-key" (include "unity-mcp-server.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/*
Pull secret name. Default `<fullname>-pull-secret`; override via
`imagePullSecret.name`. Only used when `imagePullSecret.create` is true.
*/}}
{{- define "unity-mcp-server.imagePullSecretName" -}}
{{- if .Values.imagePullSecret.name -}}
{{- .Values.imagePullSecret.name -}}
{{- else -}}
{{- printf "%s-pull-secret" (include "unity-mcp-server.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/*
Render the `imagePullSecrets:` block for a Pod spec, combining
`.Values.imagePullSecrets` (BYOIPS) with the chart-managed Secret when
`.Values.imagePullSecret.create` is true. Outputs nothing when both lists
are empty so the caller can `nindent` safely.
Usage: `{{- include "unity-mcp-server.imagePullSecretsBlock" . | nindent 6 }}`
*/}}
{{- define "unity-mcp-server.imagePullSecretsBlock" -}}
{{- $list := default (list) .Values.imagePullSecrets -}}
{{- if (default (dict) .Values.imagePullSecret).create -}}
{{- $list = append $list (dict "name" (include "unity-mcp-server.imagePullSecretName" .)) -}}
{{- end -}}
{{- if $list -}}
imagePullSecrets:
{{ toYaml $list | indent 2 }}
{{- end -}}
{{- end -}}

{{- define "unity-mcp-server.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/name: {{ include "unity-mcp-server.name" . }}
app.kubernetes.io/part-of: unity-mcp
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{- define "unity-mcp-server.selectorLabels" -}}
app.kubernetes.io/name: {{ include "unity-mcp-server.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "unity-mcp-server.annotations" -}}
{{- $top := .top -}}
{{- $extra := default dict .extra -}}
{{- $merged := merge (deepCopy $extra) (deepCopy (default dict $top.Values.commonAnnotations)) -}}
{{- if $merged -}}
{{ toYaml $merged }}
{{- end -}}
{{- end -}}
