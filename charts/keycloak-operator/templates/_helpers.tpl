{{/*
Operator name. The upstream YAML hard-codes "keycloak-operator" — this chart
keeps the same name so all RBAC subjects/refs stay self-consistent.
*/}}
{{- define "keycloak-operator.name" -}}
keycloak-operator
{{- end -}}

{{/*
Full name (currently same as name; kept for parity with other charts in the
collection if we ever introduce release-prefixed names).
*/}}
{{- define "keycloak-operator.fullname" -}}
{{ include "keycloak-operator.name" . }}
{{- end -}}

{{/*
ServiceAccount name — chart-managed when serviceAccount.create, otherwise
caller-supplied via .Values.serviceAccount.name (must already exist).
*/}}
{{- define "keycloak-operator.serviceAccountName" -}}
{{- default (include "keycloak-operator.name" .) .Values.serviceAccount.name -}}
{{- end -}}

{{/*
Common labels applied to every resource in this chart.
*/}}
{{- define "keycloak-operator.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/name: {{ include "keycloak-operator.name" . }}
app.kubernetes.io/version: {{ .Values.version | quote }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{/*
Selector labels (subset of common labels — used by the operator Deployment
and Service to match Pods).
*/}}
{{- define "keycloak-operator.selectorLabels" -}}
app.kubernetes.io/name: {{ include "keycloak-operator.name" . }}
{{- end -}}

{{/*
Per-resource annotations: merge of commonAnnotations and per-resource extra.
Returns empty when both are empty (caller should guard with `if`).
*/}}
{{- define "keycloak-operator.annotations" -}}
{{- $top := .top -}}
{{- $extra := default dict .extra -}}
{{- $merged := merge (deepCopy $extra) (deepCopy (default dict $top.Values.commonAnnotations)) -}}
{{- if $merged -}}
{{ toYaml $merged }}
{{- end -}}
{{- end -}}

{{/*
Namespace used by the cluster-wide ClusterRoleBinding subject. Defaults to
the release namespace; override via .Values.rbac.subjectNamespace when the
operator runs in a different namespace from the bootstrap RBAC subject.
*/}}
{{- define "keycloak-operator.subjectNamespace" -}}
{{- default .Release.Namespace .Values.rbac.subjectNamespace -}}
{{- end -}}

{{/*
Resolved operator image reference.
*/}}
{{- define "keycloak-operator.image" -}}
{{- $tag := default .Values.version .Values.image.tag -}}
{{ printf "%s:%s" .Values.image.repository $tag }}
{{- end -}}

{{/*
Resolved Keycloak server image reference (RELATED_IMAGE_KEYCLOAK env value).
*/}}
{{- define "keycloak-operator.serverImage" -}}
{{- $repo := default "quay.io/keycloak/keycloak" .Values.serverImage.repository -}}
{{- $tag := default .Values.version .Values.serverImage.tag -}}
{{ printf "%s:%s" $repo $tag }}
{{- end -}}

{{/*
CRD-specific annotations. Adds `helm.sh/resource-policy: keep` when the
caller opted in via .Values.crds.keep so the CRDs survive a chart uninstall.
Caller usage: include "keycloak-operator.crdAnnotations" .
*/}}
{{- define "keycloak-operator.crdAnnotations" -}}
{{- $top := . -}}
{{- $base := dict -}}
{{- if $top.Values.crds.keep -}}
{{- $_ := set $base "helm.sh/resource-policy" "keep" -}}
{{- end -}}
{{- $merged := merge (deepCopy (default dict $top.Values.commonAnnotations)) $base -}}
{{- if $merged -}}
{{ toYaml $merged }}
{{- end -}}
{{- end -}}
