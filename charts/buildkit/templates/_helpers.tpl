{{- define "buildkit.fullname" -}}
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

{{- define "buildkit.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "buildkit.serviceName" -}}
{{- default (include "buildkit.fullname" .) .Values.serviceName -}}
{{- end -}}

{{- define "buildkit.caSecretName" -}}
{{- if .Values.registry.caBundle.existingSecret -}}
{{- .Values.registry.caBundle.existingSecret -}}
{{- else -}}
{{- printf "%s-ca" (include "buildkit.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "buildkit.configMapName" -}}
{{- if .Values.configMap.nameOverride -}}
{{- .Values.configMap.nameOverride -}}
{{- else -}}
{{- printf "%s-config" (include "buildkit.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "buildkit.imagePullSecretName" -}}
{{- if .Values.imagePullSecret.name -}}
{{- .Values.imagePullSecret.name -}}
{{- else -}}
{{- printf "%s-pull-secret" (include "buildkit.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "buildkit.imagePullSecretsBlock" -}}
{{- $list := default (list) .Values.imagePullSecrets -}}
{{- if (default (dict) .Values.imagePullSecret).create -}}
{{- $list = append $list (dict "name" (include "buildkit.imagePullSecretName" .)) -}}
{{- end -}}
{{- if $list -}}
imagePullSecrets:
{{ toYaml $list | indent 2 }}
{{- end -}}
{{- end -}}

{{- define "buildkit.imageTag" -}}
{{- default .Chart.AppVersion .Values.image.tag -}}
{{- end -}}

{{/*
True when the chart should mount a CA Secret into the pod.
*/}}
{{- define "buildkit.useCaBundle" -}}
{{- if .Values.registry.caBundle.enabled -}}true{{- else -}}false{{- end -}}
{{- end -}}

{{/*
True when an init container should merge the registry CA into the OS trust
store (concat with the base image's ca-certificates.crt) and the main
container should point SSL_CERT_FILE at the result. Requires caBundle to be
enabled.
*/}}
{{- define "buildkit.useTrustStore" -}}
{{- if and .Values.registry.caBundle.enabled .Values.registry.caBundle.installToTrustStore -}}true{{- else -}}false{{- end -}}
{{- end -}}

{{/*
Image reference for the trust-store init container. Defaults to the chart's
main image (alpine-based, ships system CA bundle + sh + cat).
*/}}
{{- define "buildkit.initContainerImage" -}}
{{- $repo := default .Values.image.repository .Values.registry.caBundle.initContainerImage -}}
{{- $tag := default (include "buildkit.imageTag" .) .Values.registry.caBundle.initContainerImageTag -}}
{{- printf "%s:%s" $repo $tag -}}
{{- end -}}

{{/*
True when a buildkitd.toml ConfigMap should be rendered. Either the user
supplied an explicit `buildkitdConfig`, or the CA bundle is enabled and we
auto-render a minimal config that wires the CA path.
*/}}
{{- define "buildkit.useConfigFile" -}}
{{- if or .Values.buildkitdConfig (eq (include "buildkit.useCaBundle" .) "true") -}}true{{- else -}}false{{- end -}}
{{- end -}}

{{/*
Effective buildkitd.toml content. User-supplied `buildkitdConfig` wins;
otherwise auto-render a minimal config wiring the registry CA path.
*/}}
{{- define "buildkit.effectiveConfig" -}}
{{- if .Values.buildkitdConfig -}}
{{ .Values.buildkitdConfig }}
{{- else if eq (include "buildkit.useCaBundle" .) "true" -}}
{{- if not .Values.registry.caBundle.host -}}
{{- fail "buildkit: registry.caBundle.host is required when registry.caBundle.enabled is true and buildkitdConfig is empty (chart auto-renders a minimal config that needs the host)." -}}
{{- end -}}
debug = false

[registry."{{ .Values.registry.caBundle.host }}"]
  ca = ["{{ .Values.registry.caBundle.caPath }}"]
{{- end -}}
{{- end -}}

{{- define "buildkit.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/name: {{ include "buildkit.name" . }}
app.kubernetes.io/part-of: buildkit
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{- define "buildkit.selectorLabels" -}}
app.kubernetes.io/name: {{ include "buildkit.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: buildkit
{{- end -}}

{{- define "buildkit.annotations" -}}
{{- $top := .top -}}
{{- $extra := default dict .extra -}}
{{- $merged := merge (deepCopy $extra) (deepCopy (default dict $top.Values.commonAnnotations)) -}}
{{- if $merged -}}
{{ toYaml $merged }}
{{- end -}}
{{- end -}}
