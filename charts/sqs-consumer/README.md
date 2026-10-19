# sqs-consumer

Helm chart for [sqs-consumer](https://github.com/somaz94/sqs-consumer), an AWS SQS worker that [KEDA](https://keda.sh/) scales on queue depth, down to zero pods when the queue is empty.

<br/>

## What it deploys

| Resource | API | Purpose |
|---|---|---|
| `Deployment` | `apps/v1` | The consumer. `replicas` is omitted while KEDA is on, so the KEDA-managed HPA owns it |
| `ServiceAccount` | `v1` | Pod identity for the AWS SDK credential chain (IRSA annotation or EKS Pod Identity association) (`serviceAccount.create`) |
| `ScaledObject` | `keda.sh/v1alpha1` | `aws-sqs-queue` trigger on `consumer.queueUrl` (`keda.enabled`) |
| `TriggerAuthentication` | `keda.sh/v1alpha1` | `podIdentity.provider: aws` for the trigger (`keda.enabled` and `keda.triggerAuthentication.create`) |

With `keda.enabled: false` only the Deployment (with `replicaCount`) and the ServiceAccount render, so the chart also works on a cluster without KEDA.

<br/>

## Versioning

- Chart `version` is this chart's own SemVer.
- `appVersion` is the `ghcr.io/somaz94/sqs-consumer` release the chart was tested against, and the default image tag when `image.tag` is empty.

<br/>

## Prerequisites

- Kubernetes **1.25+**
- [KEDA](https://keda.sh/docs/latest/deploy/) **2.13+** with its CRDs, for `keda.enabled: true` (the default). 2.13 introduced the `aws` pod identity provider with `identityOwner` / `roleArn`; `keda.triggerAuthentication.externalID` needs **2.20+**, and an older CRD drops the field silently.
- An SQS queue, and an IAM role for the consumer (see [IAM](#iam))
- On EKS: IRSA (an OIDC provider for the cluster) or the EKS Pod Identity Agent

<br/>

## Install

These snippets install the latest published chart. To pin an exact chart version, add `--version <x.y.z>`; released versions are the GitHub Release tags named `sqs-consumer-<version>`.

<br/>

### OCI registry (Helm 3.8+)

```bash
helm install order-consumer oci://ghcr.io/somaz94/charts/sqs-consumer \
  --namespace sqs --create-namespace \
  --set consumer.queueUrl=https://sqs.ap-northeast-2.amazonaws.com/123456789012/order-processing-queue \
  --set consumer.awsRegion=ap-northeast-2 \
  --set 'serviceAccount.annotations.eks\.amazonaws\.com/role-arn=arn:aws:iam::123456789012:role/sqs-consumer-role'
```

<br/>

### Classic Helm repo

```bash
helm repo add somaz94 https://charts.somaz.blog
helm repo update
helm install order-consumer somaz94/sqs-consumer \
  --namespace sqs --create-namespace \
  -f my-values.yaml
```

<br/>

## Quick examples

<br/>

### Scale to zero with IRSA (default mode)

KEDA reads the IRSA role from the consumer's ServiceAccount (`identityOwner: workload`), so one role serves both the pods and the scaler. Its trust policy must also allow the KEDA operator; see [IAM](#iam).

```yaml
consumer:
  queueUrl: https://sqs.ap-northeast-2.amazonaws.com/123456789012/order-processing-queue
  awsRegion: ap-northeast-2
serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/sqs-consumer-role
    eks.amazonaws.com/sts-regional-endpoints: "true"
```

<br/>

### Watch 30 messages become 6 pods

`queueLength: "5"` is the target per pod, so 30 messages ask for 30 / 5 = 6 replicas. KEDA counts in-flight messages too (`scaleOnInFlight: true`), so one message per receive and a slow handler keep the queue deep long enough to watch it happen:

```yaml
consumer:
  queueUrl: https://sqs.ap-northeast-2.amazonaws.com/123456789012/order-processing-queue
  awsRegion: ap-northeast-2
  maxMessages: 1
  processDelay: "10s"
serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/sqs-consumer-role
keda:
  trigger:
    queueLength: "5"
```

```bash
for i in $(seq 1 30); do
  aws sqs send-message \
    --queue-url https://sqs.ap-northeast-2.amazonaws.com/123456789012/order-processing-queue \
    --message-body "order-$i" > /dev/null
done

kubectl -n sqs get hpa keda-hpa-order-consumer-sqs-consumer   # TARGETS 30/5 (avg), REPLICAS 6
kubectl -n sqs get deploy order-consumer-sqs-consumer -w       # 0 → 1 → 6, back to 0 after cooldownPeriod
```

The resource names are `<release>-sqs-consumer` unless the release name already contains `sqs-consumer` (set `fullnameOverride` to choose your own).

<br/>

### KEDA with its own role (`identityOwner: keda`)

The KEDA operator's IRSA role reads the queue depth, and the consumer's role only needs to receive and delete. Grant the operator role `sqs:GetQueueAttributes`.

```yaml
consumer:
  queueUrl: https://sqs.ap-northeast-2.amazonaws.com/123456789012/order-processing-queue
  awsRegion: ap-northeast-2
keda:
  triggerAuthentication:
    identityOwner: keda
```

This is also the mode to use with EKS Pod Identity, because `identityOwner: workload` only discovers the IRSA annotation.

<br/>

### An explicit role for KEDA (`roleArn`)

KEDA assumes the named role. `roleArn` and `identityOwner` are mutually exclusive in KEDA, so clear `identityOwner`; the chart refuses to render with both set. `externalID` is optional and only applies here.

```yaml
consumer:
  queueUrl: https://sqs.ap-northeast-2.amazonaws.com/123456789012/order-processing-queue
  awsRegion: ap-northeast-2
keda:
  triggerAuthentication:
    identityOwner: ""
    roleArn: arn:aws:iam::123456789012:role/keda-sqs-reader
```

<br/>

### Without KEDA

```yaml
consumer:
  queueUrl: https://sqs.ap-northeast-2.amazonaws.com/123456789012/order-processing-queue
  awsRegion: ap-northeast-2
keda:
  enabled: false
replicaCount: 2
```

<br/>

## Required values

- `consumer.queueUrl`: the full queue URL. The pods read it as `SQS_QUEUE_URL` and the trigger uses it as `queueURL`.
- `consumer.awsRegion`: the queue's region (`AWS_REGION` and the trigger's `awsRegion`).

The chart also refuses to render when:

- `terminationGracePeriodSeconds` is not greater than `consumer.shutdownTimeoutSeconds` (the kubelet would kill a pod that is still draining)
- `keda.triggerAuthentication.roleArn` and `keda.triggerAuthentication.identityOwner` are both set
- `keda.triggerAuthentication.externalID` is set without `roleArn`
- `keda.triggerAuthentication.create` is false and `keda.triggerAuthentication.name` is empty
- `keda.maxReplicaCount` is below `keda.minReplicaCount`, or `keda.idleReplicaCount` is not below `keda.minReplicaCount`

<br/>

## IAM

Two identities touch the queue: the consumer pods, which receive and delete messages, and the KEDA operator, which reads the queue depth.

The consumer's role needs, on the queue:

```json
{
  "Effect": "Allow",
  "Action": ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"],
  "Resource": "arn:aws:sqs:ap-northeast-2:123456789012:order-processing-queue"
}
```

Which role KEDA uses depends on `keda.triggerAuthentication`:

| Setting | KEDA uses | What the role needs |
|---|---|---|
| `identityOwner: workload` (chart default) | The role in the consumer ServiceAccount's `eks.amazonaws.com/role-arn` annotation, assumed with KEDA's own token | `sqs:GetQueueAttributes` (already in the policy above), and a trust policy that also allows the KEDA operator ServiceAccount (below) |
| `identityOwner: keda` | The KEDA operator's own role | `sqs:GetQueueAttributes` on the operator's role |
| `roleArn: <arn>` | That role | `sqs:GetQueueAttributes`, and a trust policy that lets KEDA assume it (the statement below, or `sts:AssumeRole` from the operator's role) |

In the default `workload` mode KEDA assumes the consumer's role through `sts:AssumeRoleWithWebIdentity` with the `keda-operator` ServiceAccount's token, so the role's trust policy needs a second statement next to the one for the consumer's own ServiceAccount ([KEDA docs](https://keda.sh/docs/latest/authentication-providers/aws/)):

```json
{
  "Effect": "Allow",
  "Principal": { "Federated": "arn:aws:iam::123456789012:oidc-provider/<OIDC_PROVIDER>" },
  "Action": "sts:AssumeRoleWithWebIdentity",
  "Condition": {
    "StringEquals": {
      "<OIDC_PROVIDER>:sub": "system:serviceaccount:keda:keda-operator",
      "<OIDC_PROVIDER>:aud": "sts.amazonaws.com"
    }
  }
}
```

Adjust `keda:keda-operator` if KEDA runs in another namespace or under another ServiceAccount name. Without this statement the ScaledObject reports `AccessDenied` and the Deployment never leaves zero.

The chart uses `TriggerAuthentication.spec.podIdentity.identityOwner`, not the `identityOwner` trigger metadata, which KEDA deprecated in v2.13 and will remove in v3.

<br/>

## Values reference

The tables below mirror [`values.yaml`](values.yaml), which is authoritative; [`values.schema.json`](values.schema.json) enforces the shape.

<br/>

### Consumer

Each `consumer.*` value becomes one container env variable.

| Key | Env | Notes |
|---|---|---|
| `consumer.queueUrl` | `SQS_QUEUE_URL` | **Required** |
| `consumer.awsRegion` | `AWS_REGION` | **Required** |
| `consumer.waitTimeSeconds` | `SQS_WAIT_TIME_SECONDS` | Long-poll wait, 0–20 |
| `consumer.maxMessages` | `SQS_MAX_MESSAGES` | Messages per receive, 1–10 |
| `consumer.visibilityTimeoutSeconds` | `SQS_VISIBILITY_TIMEOUT` | Keep above the worst-case processing time |
| `consumer.processDelay` | `PROCESS_DELAY` | Simulated work per message, Go duration |
| `consumer.concurrency` | `CONCURRENCY` | Messages processed in parallel per pod, 1–10 |
| `consumer.logLevel` / `consumer.logFormat` | `LOG_LEVEL` / `LOG_FORMAT` | `debug`..`error` / `json` or `text` |
| `consumer.shutdownTimeoutSeconds` | `SHUTDOWN_TIMEOUT` | Rendered as `<n>s`; drain time after SIGTERM |
| `healthPort` | `HEALTH_ADDR` | Rendered as `:<port>`; probes hit `/healthz` and `/readyz` on it |
| `extraEnv[]` | | Appended after the variables above |

<br/>

### KEDA

| Key | Purpose |
|---|---|
| `keda.enabled` | Render the ScaledObject and TriggerAuthentication, and drop `replicas` from the Deployment |
| `keda.{pollingInterval,cooldownPeriod}` | Poll period, and the delay before scaling 1 → 0 (rendered only when the ScaledObject can reach zero) |
| `keda.{minReplicaCount,maxReplicaCount,idleReplicaCount}` | Replica bounds; `minReplicaCount: 0` is scale to zero, and `idleReplicaCount` accepts only `0` |
| `keda.fallback.{failureThreshold,replicas,behavior}` | Replicas to hold while the scaler fails; not rendered when empty |
| `keda.horizontalPodAutoscalerConfig` | `advanced.horizontalPodAutoscalerConfig`; defaults to a 60s scale-down stabilization window |
| `keda.trigger.{queueLength,activationQueueLength}` | Target messages per pod, and the depth that wakes the Deployment from zero |
| `keda.trigger.{scaleOnInFlight,scaleOnDelayed}` | Count in-flight and delayed messages toward the depth |
| `keda.trigger.metadataExtra` | Extra trigger metadata, e.g. `awsEndpoint` |
| `keda.triggerAuthentication.{create,name,kind}` | Render a TriggerAuthentication, or reference an existing (Cluster)TriggerAuthentication |
| `keda.triggerAuthentication.{identityOwner,roleArn,externalID}` | `podIdentity` settings; see [IAM](#iam) |
| `keda.scaledObjectExtra` | Merged into the ScaledObject `spec` last |

<br/>

### Pod and metadata

| Key | Purpose |
|---|---|
| `image.{repository,tag,pullPolicy}` | Tag defaults to `appVersion` |
| `imagePullSecrets` | Existing pull secrets |
| `replicaCount` | Used only with `keda.enabled: false` |
| `terminationGracePeriodSeconds` | Must exceed `consumer.shutdownTimeoutSeconds` |
| `serviceAccount.{create,name,annotations,automountServiceAccountToken}` | IRSA annotation goes in `annotations` |
| `resources`, `livenessProbe`, `readinessProbe` | Container resources and probes |
| `podSecurityContext` / `securityContext` | Non-root, read-only root filesystem, all capabilities dropped, `RuntimeDefault` seccomp |
| `podAnnotations`, `podLabels`, `nodeSelector`, `tolerations`, `affinity`, `topologySpreadConstraints`, `priorityClassName` | Pod scheduling and metadata |
| `extraVolumes` / `extraVolumeMounts` | e.g. an `emptyDir` on `/tmp` if the image needs a writable path |
| `commonLabels` / `commonAnnotations` / `resourceMetadata.*` | Labels and annotations per resource kind |
| `specExtra` / `podTemplateExtra` | Escape hatches into the Deployment spec and Pod spec |

<br/>

## License

[Apache-2.0](../../LICENSE)
