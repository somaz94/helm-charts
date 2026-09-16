{{/*
Chart name used to derive resource names and as the label value.
Defaults to the Helm release name; overridable via .Values.name.
*/}}
{{- define "elasticsearch-eck.fullname" -}}
{{- default .Release.Name .Values.name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Common labels applied to every resource in this chart.
Caller may extend via .Values.commonLabels.
*/}}
{{- define "elasticsearch-eck.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/name: {{ include "elasticsearch-eck.fullname" . }}
app.kubernetes.io/part-of: elastic-stack
app.kubernetes.io/component: elasticsearch
app.kubernetes.io/version: {{ .Values.version | quote }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{/*
Per-resource annotations: merge of commonAnnotations and per-resource extra.
Usage: include "elasticsearch-eck.annotations" (dict "top" $top "extra" .Values.resourceMetadata.httproute.annotations)
Returns empty when both are empty (caller should guard with `if`).
*/}}
{{- define "elasticsearch-eck.annotations" -}}
{{- $top := .top -}}
{{- $extra := default dict .extra -}}
{{- $merged := merge (deepCopy $extra) (deepCopy (default dict $top.Values.commonAnnotations)) -}}
{{- if $merged -}}
{{ toYaml $merged }}
{{- end -}}
{{- end -}}

{{/*
Service name ECK generates for the HTTP endpoint (<name>-es-http).
*/}}
{{- define "elasticsearch-eck.httpServiceName" -}}
{{ printf "%s-es-http" (include "elasticsearch-eck.fullname" .) }}
{{- end -}}

{{/*
Secret name ECK generates for the public HTTP certs. Source of `ca.crt`
for BackendTLSPolicy (copied into a ConfigMap via helm lookup).
*/}}
{{- define "elasticsearch-eck.httpCertsSecretName" -}}
{{ printf "%s-es-http-certs-public" (include "elasticsearch-eck.fullname" .) }}
{{- end -}}

{{/*
ConfigMap name this chart renders for the CA bundle (used by BackendTLSPolicy
when `caCertificateRef.kind: ConfigMap` with empty `name`).
*/}}
{{- define "elasticsearch-eck.caConfigMapName" -}}
{{ printf "%s-ca" (include "elasticsearch-eck.fullname" .) }}
{{- end -}}

{{/*
Shell function used by the privileged sysctl init container.

`apply <key> <want>` raises a sysctl to <want> only when the node currently sits
BELOW it -- a floor, never an assignment. `sysctl -w` on its own overwrites
unconditionally, which silently regresses a node that was already tuned higher,
and because the write is node-level and outlives the pod, every other workload
scheduled there inherits the lowered value.

Falls back to a plain write when either side is not a plain integer, so
multi-field sysctls (e.g. net.ipv4.tcp_rmem "4096 87380 6291456") still work.
*/}}
{{- define "elasticsearch-eck.sysctlApplyFn" -}}
apply() {
  key=$1; want=$2
  cur=$(sysctl -n "$key" 2>/dev/null) || cur=""
  case "$want" in *[!0-9]*) sysctl -w "$key=$want"; return;; esac
  case "$cur" in ''|*[!0-9]*) sysctl -w "$key=$want"; return;; esac
  if [ "$cur" -lt "$want" ]; then
    sysctl -w "$key=$want"
  else
    echo "$key: node already at $cur (>= $want), leaving as is"
  fi
}
{{- end -}}
