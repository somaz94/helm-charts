{{/*
Common labels applied to every resource in this chart.
Caller may extend via .Values.commonLabels.
*/}}
{{- define "karpenter-cr.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/part-of: karpenter
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{/*
Per-resource annotations: merge of commonAnnotations and per-resource extra.
Usage: include "karpenter-cr.annotations" (dict "top" $top "extra" $entry.annotations)
Returns empty when both are empty (caller should guard with `if`).
*/}}
{{- define "karpenter-cr.annotations" -}}
{{- $top := .top -}}
{{- $extra := default dict .extra -}}
{{- $merged := merge (deepCopy $extra) (deepCopy (default dict $top.Values.commonAnnotations)) -}}
{{- if $merged -}}
{{ toYaml $merged }}
{{- end -}}
{{- end -}}

{{/*
Discovery selector terms ({ tags: { <discoveryKey>: <clusterName> } }) used as the
default subnet / security-group selector. Requires .Values.clusterName.
*/}}
{{- define "karpenter-cr.discoverySelector" -}}
- tags:
    {{ .Values.discoveryKey }}: {{ required "clusterName is required to build discovery selector terms" .Values.clusterName | quote }}
{{- end -}}
