{{/*
Chart name used to derive resource names and as the label value.
Defaults to the Helm release name; overridable via .Values.name.
*/}}
{{- define "kibana-eck.fullname" -}}
{{- default .Release.Name .Values.name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Common labels applied to every resource in this chart.
*/}}
{{- define "kibana-eck.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/name: {{ include "kibana-eck.fullname" . }}
app.kubernetes.io/part-of: elastic-stack
app.kubernetes.io/component: kibana
app.kubernetes.io/version: {{ .Values.version | quote }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{/*
Per-resource annotations: merge of commonAnnotations and per-resource extra.
Usage: include "kibana-eck.annotations" (dict "top" $top "extra" .Values.resourceMetadata.<resource>.annotations)
*/}}
{{- define "kibana-eck.annotations" -}}
{{- $top := .top -}}
{{- $extra := default dict .extra -}}
{{- $merged := merge (deepCopy $extra) (deepCopy (default dict $top.Values.commonAnnotations)) -}}
{{- if $merged -}}
{{ toYaml $merged }}
{{- end -}}
{{- end -}}

{{/*
Service name ECK generates for the HTTP endpoint (<name>-kb-http).
*/}}
{{- define "kibana-eck.httpServiceName" -}}
{{ printf "%s-kb-http" (include "kibana-eck.fullname" .) }}
{{- end -}}
