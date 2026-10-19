{{- define "sqs-consumer.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "sqs-consumer.fullname" -}}
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

{{- define "sqs-consumer.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/name: {{ include "sqs-consumer.name" . }}
app.kubernetes.io/part-of: sqs-consumer
app.kubernetes.io/component: consumer
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{- define "sqs-consumer.selectorLabels" -}}
app.kubernetes.io/name: {{ include "sqs-consumer.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
Merge commonAnnotations with a per-resource extras dict; extras win.
Usage: include "sqs-consumer.annotations" (dict "top" . "extra" <dict>)
*/}}
{{- define "sqs-consumer.annotations" -}}
{{- $top := .top -}}
{{- $extra := default dict .extra -}}
{{- $merged := merge (deepCopy $extra) (deepCopy (default dict $top.Values.commonAnnotations)) -}}
{{- if $merged -}}
{{ toYaml $merged }}
{{- end -}}
{{- end -}}

{{- define "sqs-consumer.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "sqs-consumer.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{- define "sqs-consumer.triggerAuthenticationName" -}}
{{- default (include "sqs-consumer.fullname" .) .Values.keda.triggerAuthentication.name -}}
{{- end -}}

{{- define "sqs-consumer.image" -}}
{{- printf "%s:%s" .Values.image.repository (default .Chart.AppVersion .Values.image.tag) -}}
{{- end -}}

{{/*
Render-time checks the schema cannot express. Included once, from deployment.yaml.
*/}}
{{- define "sqs-consumer.validate" -}}
{{- if not .Values.consumer.queueUrl -}}
{{- fail "sqs-consumer: consumer.queueUrl is required (e.g. https://sqs.<region>.amazonaws.com/<account-id>/<queue-name>)." -}}
{{- end -}}
{{- if not .Values.consumer.awsRegion -}}
{{- fail "sqs-consumer: consumer.awsRegion is required (e.g. ap-northeast-2)." -}}
{{- end -}}
{{- if le (int .Values.terminationGracePeriodSeconds) (int .Values.consumer.shutdownTimeoutSeconds) -}}
{{- fail (printf "sqs-consumer: terminationGracePeriodSeconds (%d) must be greater than consumer.shutdownTimeoutSeconds (%d), or the kubelet kills the pod before in-flight messages drain." (int .Values.terminationGracePeriodSeconds) (int .Values.consumer.shutdownTimeoutSeconds)) -}}
{{- end -}}
{{- if .Values.keda.enabled -}}
{{- $k := .Values.keda -}}
{{- if lt (int $k.maxReplicaCount) (int $k.minReplicaCount) -}}
{{- fail (printf "sqs-consumer: keda.maxReplicaCount (%d) must be >= keda.minReplicaCount (%d)." (int $k.maxReplicaCount) (int $k.minReplicaCount)) -}}
{{- end -}}
{{- if and (not (kindIs "invalid" $k.idleReplicaCount)) (ge (int $k.idleReplicaCount) (int $k.minReplicaCount)) -}}
{{- fail (printf "sqs-consumer: keda.idleReplicaCount (%d) must be lower than keda.minReplicaCount (%d); KEDA rejects it otherwise." (int $k.idleReplicaCount) (int $k.minReplicaCount)) -}}
{{- end -}}
{{- $ta := $k.triggerAuthentication -}}
{{- if $ta.create -}}
{{- if and $ta.roleArn $ta.identityOwner -}}
{{- fail (printf "sqs-consumer: keda.triggerAuthentication.roleArn and keda.triggerAuthentication.identityOwner (%q) are mutually exclusive in KEDA's podIdentity. Set identityOwner to \"\" to use roleArn, or clear roleArn." $ta.identityOwner) -}}
{{- end -}}
{{- if and $ta.externalID (not $ta.roleArn) -}}
{{- fail "sqs-consumer: keda.triggerAuthentication.externalID only applies with roleArn (KEDA passes it to sts:AssumeRole)." -}}
{{- end -}}
{{- else if not $ta.name -}}
{{- fail "sqs-consumer: keda.triggerAuthentication.name is required when keda.triggerAuthentication.create is false." -}}
{{- end -}}
{{- end -}}
{{- end -}}
