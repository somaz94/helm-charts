{{/*
Chart name used to derive resource names. Defaults to the Helm release name;
overridable via .Values.name.
*/}}
{{- define "keycloak-cr.fullname" -}}
{{- default .Release.Name .Values.name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Common labels applied to every resource in this chart.
Caller may extend via .Values.commonLabels.
*/}}
{{- define "keycloak-cr.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/name: {{ include "keycloak-cr.fullname" . }}
app.kubernetes.io/part-of: keycloak
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{/*
Per-resource annotations: merge of commonAnnotations and per-resource extra.
Usage: include "keycloak-cr.annotations" (dict "top" $top "extra" .Values.resourceMetadata.keycloak.annotations)
Returns empty when both are empty (caller should guard with `if`).
*/}}
{{- define "keycloak-cr.annotations" -}}
{{- $top := .top -}}
{{- $extra := default dict .extra -}}
{{- $merged := merge (deepCopy $extra) (deepCopy (default dict $top.Values.commonAnnotations)) -}}
{{- if $merged -}}
{{ toYaml $merged }}
{{- end -}}
{{- end -}}

{{/*
Resolved name of the DB credentials Secret. Either consumer-supplied via
keycloak.db.existingSecret, or the chart-rendered Secret name when dbSecret.enabled.
*/}}
{{- define "keycloak-cr.dbSecretName" -}}
{{- $top := . -}}
{{- if $top.Values.keycloak.db.existingSecret -}}
{{ $top.Values.keycloak.db.existingSecret }}
{{- else if $top.Values.dbSecret.enabled -}}
{{ default (printf "%s-db-credentials" (include "keycloak-cr.fullname" $top)) $top.Values.dbSecret.name }}
{{- end -}}
{{- end -}}

{{/*
Resolved name of the bootstrap admin user Secret.
*/}}
{{- define "keycloak-cr.adminUserSecretName" -}}
{{- $top := . -}}
{{- if $top.Values.keycloak.bootstrapAdmin.userSecret -}}
{{ $top.Values.keycloak.bootstrapAdmin.userSecret }}
{{- else if $top.Values.adminSecret.enabled -}}
{{ default (printf "%s-bootstrap-admin" (include "keycloak-cr.fullname" $top)) $top.Values.adminSecret.name }}
{{- end -}}
{{- end -}}

{{/*
Default Service name the Keycloak Operator renders for a Keycloak CR
(`<name>-service`). Used as the HTTPRoute backendRef default.
*/}}
{{- define "keycloak-cr.serviceName" -}}
{{ printf "%s-service" (include "keycloak-cr.fullname" .) }}
{{- end -}}

{{/*
Pre-render values validation. Called from the primary CR template so any
misconfiguration fails the install before resources are admitted.
*/}}
{{- define "keycloak-cr.validate" -}}
{{- $routes := list -}}
{{- if .Values.httproute.enabled }}{{- $routes = append $routes "httproute.enabled" -}}{{- end -}}
{{- if .Values.ingress.enabled }}{{- $routes = append $routes "ingress.enabled" -}}{{- end -}}
{{- if .Values.keycloak.ingress.enabled }}{{- $routes = append $routes "keycloak.ingress.enabled" -}}{{- end -}}
{{- if gt (len $routes) 1 -}}
{{- fail (printf "keycloak-cr: pick exactly one routing method, got: %s. Choose httproute.enabled (Gateway API), ingress.enabled (chart-rendered Ingress) OR keycloak.ingress.enabled (operator-rendered Ingress)." (join ", " $routes)) -}}
{{- end -}}
{{- if and .Values.realmImport.enabled (empty .Values.realmImport.realm) -}}
{{- fail "keycloak-cr: realmImport.enabled is true but realmImport.realm is empty. Provide an inline RealmRepresentation, or run helm with --set-file realmImport.realm=path/to/realm.json." -}}
{{- end -}}
{{- end -}}
