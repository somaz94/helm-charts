# external-secrets-cr

Data-driven **External Secrets Operator (ESO) configuration** custom resources, deployed as a Helm release alongside the upstream external-secrets chart.

The upstream [`external-secrets/external-secrets`](https://github.com/external-secrets/external-secrets) chart installs the controller, webhook and CRDs but **does not template config CRs** (`SecretStore`, `ExternalSecret`, `PushSecret`, ...) — those are left for you to apply out-of-band (typically `kubectl apply -f` in a post-sync hook). This chart closes that gap so the ESO configuration is managed declaratively in Git, versioned, and rolled out with the same `helm` / `helmfile` flow as the operator.

<br/>

## What it deploys

| Resource | API | Scope | Created from |
|---|---|---|---|
| `SecretStore` | `external-secrets.io/v1` | Namespaced | `secretStores[]` |
| `ClusterSecretStore` | `external-secrets.io/v1` | Cluster | `clusterSecretStores[]` |
| `ExternalSecret` | `external-secrets.io/v1` | Namespaced | `externalSecrets[]` |
| `ClusterExternalSecret` | `external-secrets.io/v1` | Cluster | `clusterExternalSecrets[]` |
| `PushSecret` | `external-secrets.io/v1alpha1` | Namespaced | `pushSecrets[]` |

Every list defaults to empty, so an unconfigured `helm install` creates nothing.

<br/>

## Prerequisites

- Kubernetes >= 1.25
- External Secrets Operator (controller + webhook) and its CRDs already installed — typically via the upstream `external-secrets/external-secrets` chart with `installCRDs: true`. This chart only creates config CRs; it does not install ESO itself or its CRDs.
- `PushSecret` requires the `external-secrets.io/v1alpha1` CRD (shipped by ESO); omit `pushSecrets` if your ESO build does not enable it.

<br/>

## Install

OCI registry:

```bash
helm install eso-config oci://ghcr.io/somaz94/charts/external-secrets-cr \
  --namespace external-secrets \
  -f my-values.yaml
```

Classic Helm repo:

```bash
helm repo add somaz94 https://charts.somaz.blog
helm install eso-config somaz94/external-secrets-cr \
  --namespace external-secrets \
  -f my-values.yaml
```

<br/>

## Quick examples

<br/>

### AWS Secrets Manager via EKS Pod Identity / IRSA

A cluster-wide store with no `auth` block — ESO falls back to the pod's default AWS credential chain, which the Pod Identity agent (or IRSA) populates.

```yaml
clusterSecretStores:
  - name: aws-secretsmanager
    provider:
      aws:
        service: SecretsManager
        region: eu-central-1

externalSecrets:
  - name: app-db
    namespace: app
    secretStoreRef:
      name: aws-secretsmanager
      kind: ClusterSecretStore
    target:
      name: app-db
      creationPolicy: Owner
    data:
      - secretKey: password
        remoteRef:
          key: prod/app-db
          property: password
```

<br/>

### HashiCorp Vault (namespaced store)

```yaml
secretStores:
  - name: vault-backend
    namespace: app
    provider:
      vault:
        server: https://vault.example.com:8200
        path: secret
        version: v2
        auth:
          kubernetes:
            mountPath: kubernetes
            role: eso

externalSecrets:
  - name: app-config
    namespace: app
    secretStoreRef:
      name: vault-backend
      kind: SecretStore
    dataFrom:
      - extract:
          key: app/config
```

<br/>

### Fan one secret out to many namespaces

```yaml
clusterExternalSecrets:
  - name: registry-pull
    namespaceSelector:
      matchLabels:
        eso.example.com/pull: "true"
    externalSecretSpec:
      secretStoreRef:
        name: aws-secretsmanager
        kind: ClusterSecretStore
      target:
        name: registry-pull
      data:
        - secretKey: .dockerconfigjson
          remoteRef:
            key: prod/registry-dockerconfig
```

<br/>

### Push a generated Secret back to the provider

```yaml
pushSecrets:
  - name: mirror-to-aws
    namespace: app
    secretStoreRefs:
      - name: aws-secretsmanager
        kind: ClusterSecretStore
    selector:
      secret:
        name: app-generated
    data:
      - match:
          secretKey: token
          remoteRef:
            remoteKey: prod/app-generated-token
    updatePolicy: Replace
    deletionPolicy: None
```

<br/>

## Values reference

<br/>

### Shared metadata

| Key | Type | Default | Description |
|---|---|---|---|
| `commonLabels` | map | `{}` | Labels added to every resource. |
| `commonAnnotations` | map | `{}` | Annotations added to every resource. |

<br/>

### `secretStores[]` / `clusterSecretStores[]`

| Key | Type | Required | Description |
|---|---|---|---|
| `name` | string | yes | Resource name. |
| `namespace` | string | no | Target namespace (`secretStores` only; default: release namespace). |
| `provider` | map | yes | Backend-specific provider block, passed through verbatim. |
| `refreshInterval` | integer | no | Store refresh interval in **seconds** (`0`/empty = controller default). Unlike `ExternalSecret`/`PushSecret`, `(Cluster)SecretStore` takes an integer here, not a duration string. |
| `retrySettings` | map | no | `{ maxRetries, retryInterval }`. |
| `conditions` | list | no | Namespace/label conditions restricting use of the store. |
| `controller` | string | no | Controller class that should process this store. |
| `labels` / `annotations` | map | no | Extra metadata on this resource. |
| `specExtra` | map | no | Arbitrary YAML merged into `spec`. |

<br/>

### `externalSecrets[]`

| Key | Type | Required | Description |
|---|---|---|---|
| `name` | string | yes | ExternalSecret name. |
| `namespace` | string | no | Target namespace (default: release namespace). |
| `refreshInterval` | string | no | Sync interval (`1h`; `0` disables). |
| `secretStoreRef` | map | no | `{ name, kind: SecretStore\|ClusterSecretStore }`. |
| `target` | map | no | `{ name, creationPolicy, deletionPolicy, template }`. |
| `data` | list | no | List of `{ secretKey, remoteRef }`. |
| `dataFrom` | list | no | List of `extract` / `find` blocks. |
| `labels` / `annotations` / `specExtra` | map | no | Extra metadata / escape hatch. |

<br/>

### `clusterExternalSecrets[]`

| Key | Type | Required | Description |
|---|---|---|---|
| `name` | string | yes | ClusterExternalSecret name. |
| `externalSecretName` | string | no | Name of the ExternalSecret created in each namespace. |
| `namespaceSelector` | map | no | Label selector picking target namespaces. |
| `namespaces` | list | no | Explicit namespace name list. |
| `namespaceSelectors` | list | no | List of label selectors. |
| `refreshTime` | string | no | How often to reconcile the namespace set. |
| `externalSecretSpec` | map | yes | The ExternalSecret spec projected into each namespace. |
| `labels` / `annotations` / `specExtra` | map | no | Extra metadata / escape hatch. |

<br/>

### `pushSecrets[]`

| Key | Type | Required | Description |
|---|---|---|---|
| `name` | string | yes | PushSecret name. |
| `namespace` | string | no | Target namespace (default: release namespace). |
| `refreshInterval` | string | no | Push interval. |
| `secretStoreRefs` | list | no | List of `{ name, kind }` backends to push to. |
| `selector` | map | no | `{ secret: { name } }` source Secret selector. |
| `data` | list | no | List of `{ match: { secretKey, remoteRef } }`. |
| `template` | map | no | Template applied to the pushed payload. |
| `updatePolicy` | string | no | `Replace` \| `IfNotExists`. |
| `deletionPolicy` | string | no | `Delete` \| `None`. |
| `labels` / `annotations` / `specExtra` | map | no | Extra metadata / escape hatch. |

<br/>

## License

[Apache-2.0](../../LICENSE)
