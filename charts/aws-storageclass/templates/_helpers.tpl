{{/*
Common labels applied to every StorageClass in this chart.
Caller may extend via .Values.commonLabels.
*/}}
{{- define "aws-storageclass.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/part-of: aws-storageclass
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{/*
Per-StorageClass annotations: merge of commonAnnotations, per-entry extra, and
the is-default-class marker when requested.
Usage:
  include "aws-storageclass.annotations" (dict "top" $top "extra" $sc.annotations "isDefault" $isDefault)
Returns empty when nothing applies (caller should guard with `if`).
*/}}
{{- define "aws-storageclass.annotations" -}}
{{- $top := .top -}}
{{- $extra := default dict .extra -}}
{{- $merged := merge (deepCopy $extra) (deepCopy (default dict $top.Values.commonAnnotations)) -}}
{{- if .isDefault -}}
{{- $_ := set $merged "storageclass.kubernetes.io/is-default-class" "true" -}}
{{- end -}}
{{- if $merged -}}
{{ toYaml $merged }}
{{- end -}}
{{- end -}}
