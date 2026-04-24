# elasticsearch-eck

A Helm chart for Elasticsearch on Kubernetes via the [ECK operator](https://github.com/elastic/cloud-on-k8s).

The chart renders the ECK `Elasticsearch` Custom Resource plus a handful of optional siblings (elastic-user Secret, HTTPRoute, BackendTLSPolicy, PodDisruptionBudget, ServiceMonitor). Defaults target a single-node dev/staging cluster; production HA is opt-in via `nodeSets[]`.

<br/>

## What it deploys

| Resource | API | Purpose |
|---|---|---|
| `Elasticsearch` | `elasticsearch.k8s.elastic.co/v1` | The cluster CR. ECK reconciles StatefulSets, Services, Secrets. |
| `Secret` (elastic user) | `v1` | Optional. Pre-seeded `elastic` user password when `elasticPassword` is set. |
| `PodDisruptionBudget` | `policy/v1` | Optional (external mode). Prefer `podDisruptionBudget.native: true` which renders PDB inside the CR. |
| `HTTPRoute` | `gateway.networking.k8s.io/v1` | Optional. Gateway API route for external access. |
| `BackendTLSPolicy` | `gateway.networking.k8s.io/v1` | Optional. Verifies ECK self-signed HTTPS cert from the Gateway. Points directly at the ECK-managed `*-es-http-certs-public` Secret by default. |
| `ServiceMonitor` | `monitoring.coreos.com/v1` | Optional. Prometheus scrape config for `/_prometheus/metrics`. |

<br/>

## Versioning

This chart follows Helm's standard semantics:

- `Chart.yaml` **version** — the chart's own SemVer. Bumped manually by the maintainer via `make bump CHART=elasticsearch-eck LEVEL=patch|minor|major` for template or schema changes.
- `Chart.yaml` **appVersion** — the Elastic Stack version shipped by the chart (default `values.version`). Bumped by `./upgrade.sh` when a new Elasticsearch GA lands. Chart version is **not** automatically mirrored.
- `values.yaml` **version** — the `spec.version` rendered into the Elasticsearch CR. Defaults to `appVersion`; override to pin a different version at install time.
- `values.yaml` **image** — optional full image reference override (private mirrors, air-gapped registries).

<br/>

## Prerequisites

- Kubernetes **1.25+**
- [ECK Operator](https://github.com/elastic/cloud-on-k8s) installed (provides the `elasticsearch.k8s.elastic.co` CRDs):
  ```bash
  helm repo add elastic https://helm.elastic.co
  helm install eck-operator elastic/eck-operator -n elastic-system --create-namespace
  ```
- **A StorageClass for the ES data PVC.** You MUST supply one that exists in your cluster — this chart ships **no StorageClass**. Common choices:

  | Environment | Typical StorageClass |
  |---|---|
  | Bare-metal / NFS | `nfs-client`, `nfs-subdir-external-provisioner` |
  | AWS EKS | `gp3`, `gp2`, `io2` |
  | GCP GKE | `standard`, `standard-rwo`, `premium-rwo` |
  | Azure AKS | `managed-csi`, `managed-premium` |
  | On-prem Ceph | `ceph-block`, `rook-ceph-block` |
  | Local-path (kind/k3s dev only) | `local-path`, `standard` |

  Set it in values:
  ```yaml
  nodeSets:
    - name: default
      storage:
        storageClass: nfs-client    # ← put YOUR cluster's SC here
        size: 30Gi
  ```
  Leave `storageClass: ""` only if your cluster has a default StorageClass marked `storageclass.kubernetes.io/is-default-class: "true"`.
- For `httproute.enabled: true`: [Gateway API](https://gateway-api.sigs.k8s.io/) CRDs + a Gateway controller (e.g. NGINX Gateway Fabric)
- For `serviceMonitor.enabled: true`: [Prometheus Operator](https://github.com/prometheus-operator/prometheus-operator)

Check what's available in your cluster:
```bash
kubectl get storageclass
```

<br/>

## Install

### OCI registry (Helm 3.8+)

```bash
helm install es oci://ghcr.io/somaz94/charts/elasticsearch-eck \
  --version 0.1.1 \
  --namespace logging --create-namespace \
  -f my-values.yaml
```

<br/>

### Classic Helm repo

```bash
helm repo add somaz94 https://charts.somaz.blog
helm repo update
helm install es somaz94/elasticsearch-eck \
  --namespace logging --create-namespace \
  -f my-values.yaml
```

<br/>

## Quick examples

### 1. Minimal (single-node, dev/staging)

One all-roles node, 30 GiB PVC. **Pick a StorageClass that exists in your cluster** (see Prerequisites above):

```yaml
# my-values.yaml
elasticPassword: "changeme"
nodeSets:
  - name: default
    count: 1
    storage:
      storageClass: nfs-client    # ← replace with your SC (gp3 / standard / ceph-block / ...)
      size: 30Gi
```

```bash
helm install es oci://ghcr.io/somaz94/charts/elasticsearch-eck \
  --namespace logging --create-namespace \
  -f my-values.yaml
```

Omitting `storageClass` falls back to the cluster's default SC — only works if one is marked default (`kubectl get sc` shows `(default)` next to it).

<br/>

### 2. Production HA (3 master + 3 data, zero-downtime rolling)

> **Pick block storage**, not NFS. NFS RWO works for single-node dev but causes data corruption risk with multiple writers. AWS: `gp3`/`io2`, GCP: `premium-rwo`, Ceph: `ceph-block`, vSphere: `vsphere-csi`.

> Zero-downtime rolling upgrades in HA topology are verified against chart 0.1.1. See [../../docs/ha-rolling-verification.md](../../docs/ha-rolling-verification.md) for the test procedure, load generator, and result log.

```yaml
nodeSets:
  - name: master
    count: 3
    roles: [master]
    resources:
      requests: {cpu: 500m, memory: 2Gi}
      limits:   {cpu: 1000m, memory: 2Gi}
    storage:
      storageClass: ceph-block     # ← your block SC (NOT NFS)
      size: 10Gi
    topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: kubernetes.io/hostname
        whenUnsatisfiable: DoNotSchedule
        labelSelector:
          matchLabels:
            elasticsearch.k8s.elastic.co/node-master: "true"

  - name: data
    count: 3
    roles: [data, ingest, transform]
    resources:
      requests: {cpu: 1000m, memory: 8Gi}
      limits:   {cpu: 4000m, memory: 8Gi}
    storage:
      storageClass: ceph-block     # ← your block SC (NOT NFS)
      size: 500Gi
    topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: kubernetes.io/hostname
        whenUnsatisfiable: DoNotSchedule
        labelSelector:
          matchLabels:
            elasticsearch.k8s.elastic.co/node-data: "true"

podDisruptionBudget:
  native: true
  maxUnavailable: 1

updateStrategy:
  changeBudget:
    maxSurge: 1
    maxUnavailable: 1
```

<br/>

### 3. Behind a Gateway (NGF) with TLS verification

```yaml
httproute:
  enabled: true
  parentRefs:
    - name: ngf
      namespace: nginx-gateway
  hostnames:
    - elasticsearch.example.com
  rules:
    - matches:
        - path: {type: PathPrefix, value: /}
      backendRefs:
        - port: 9200

backendTLSPolicy:
  enabled: true
```

> The `BackendTLSPolicy` references the ECK-managed Secret `<name>-es-http-certs-public` directly (it already contains `ca.crt`). NGINX Gateway Fabric supports the `Secret` kind for `caCertificateRefs`.
>
> **Gateway API Core-only implementations** (Secret not supported): set `backendTLSPolicy.caCertificateRef.kind: ConfigMap` and provision a ConfigMap `<fullname>-ca` with key `ca.crt` out-of-band — e.g. via the [Reflector](https://github.com/emberstack/kubernetes-reflector) operator reflecting the ECK Secret, via External Secrets, or via a one-shot kubectl command after the ECK Secret is ready.
>
> **Migrating from 0.1.x (< 0.1.3)**: the chart used to render the `<fullname>-ca` ConfigMap automatically via `helm lookup`. On upgrade to 0.1.3+, Helm garbage-collects that ConfigMap because it's no longer in the release manifest. NGF users keep working transparently (BTP now points at the Secret). For other implementations see above.

<br/>

### 4. Advanced — escape hatches

Every ECK CR field is reachable. If something is not surfaced as a named value, inject it via `specExtra`, `podTemplateExtra`, or `nodeSets[].nodeSetExtra`:

```yaml
secureSettings:
  - secretName: s3-snapshot-creds

specExtra:
  revisionHistoryLimit: 5

nodeSets:
  - name: default
    count: 1
    podTemplateExtra:
      spec:
        hostNetwork: false
        dnsPolicy: ClusterFirst
    nodeSetExtra:
      podManagementPolicy: Parallel
```

<br/>

## Values reference

<br/>

### Top-level

| Key | Default | Description |
|---|---|---|
| `commonLabels` | `{}` | Labels applied to every resource. |
| `commonAnnotations` | `{}` | Annotations applied to every resource (merged with per-resource extras). |
| `resourceMetadata` | `{}` | Per-resource `labels`/`annotations` override. Keys: `elasticsearch`, `elasticUserSecret`, `podDisruptionBudget`, `httproute`, `backendTLSPolicy`, `serviceMonitor`. |
| `name` | `""` | CR name. Empty → Helm release name. |
| `version` | `"9.3.3"` | Elastic Stack version (ES `spec.version`). Bump via `./upgrade.sh`. |
| `image` | `""` | Optional image override (private mirrors / air-gapped). |
| `elasticPassword` | `""` | Password for the `elastic` superuser. Empty → ECK auto-generates. |
| `serviceAccountName` | `""` | Optional SA for IRSA / restricted RBAC. |
| `http` | ECK self-signed TLS | Passthrough to `spec.http` (tls, service). |
| `transport` | `{}` | Passthrough to `spec.transport`. |
| `secureSettings` | `[]` | ECK secureSettings array (keystore sources). |
| `auth` | `{}` | ECK `spec.auth` (roles, fileRealm). |
| `remoteClusters` | `[]` | CCR/CCS connections. |
| `monitoring` | `{}` | Stack Monitoring config. |
| `updateStrategy` | `{}` | ECK changeBudget for rolling updates. |
| `specExtra` | `{}` | **Escape hatch**: extra fields merged into `spec`. |
| `sysctlInitContainer.enabled` | `true` | Privileged init container setting `vm.max_map_count=262144`. |

<br/>

### `nodeSets[]`

| Key | Default | Description |
|---|---|---|
| `name` | _required_ | nodeSet name (used in StatefulSet name). |
| `count` | _required_ | Number of pods in the StatefulSet. |
| `roles` | _(all roles)_ | `node.roles` setting. |
| `config` | `{node.store.allow_mmap: false}` | Free-form `elasticsearch.yml` content (merged with `node.roles`). |
| `resources` | `100m/2Gi → 1000m/2Gi` | Container resources for the `elasticsearch` container. |
| `storage.storageClass` | `""` | **PVC StorageClass — provide your own.** Empty → cluster default SC (only works if one is marked default). See Prerequisites for common SC names per environment. |
| `storage.size` | `30Gi` | PVC size for the default `elasticsearch-data` volume. |
| `storage.accessModes` | `[ReadWriteOnce]` | PVC accessModes. |
| `volumeClaimTemplates` | `[]` | Extra PVCs (beyond the default `elasticsearch-data`). Full ECK shape. |
| `nodeSelector` / `tolerations` / `affinity` / `topologySpreadConstraints` | `{}`/`[]` | Pod scheduling. |
| `priorityClassName` | `""` | Pod priority class. |
| `initContainers` / `sidecars` | `[]` | Extra containers (full container spec). |
| `env` / `envFrom` / `volumes` / `volumeMounts` | `[]` | Extra env/volume config on the elasticsearch container. |
| `livenessProbe` / `readinessProbe` / `startupProbe` / `lifecycle` | `{}` | Container probes & lifecycle. |
| `podSecurityContext` / `securityContext` | `{}` | Pod-level and container-level security contexts. |
| `serviceAccountName` | `""` | Per-nodeSet SA override (rare). |
| `containerExtra` | `{}` | **Escape hatch**: merged into the elasticsearch container. |
| `podTemplateExtra` | `{}` | **Escape hatch**: merged into `spec.podTemplate`. |
| `nodeSetExtra` | `{}` | **Escape hatch**: merged into the nodeSet entry. |

<br/>

### `podDisruptionBudget`

| Key | Default | Description |
|---|---|---|
| `native` | `false` | Render PDB inside the Elasticsearch CR (ECK-managed). Recommended. |
| `external` | `false` | Render a separate `policy/v1 PodDisruptionBudget`. Use only when ECK native is insufficient. |
| `maxUnavailable` | `1` | Applies to both modes. |
| `minAvailable` | `null` | Alternative to `maxUnavailable` (mutually exclusive). |

<br/>

### `httproute` / `backendTLSPolicy`

Standard Gateway API HTTPRoute fields; see the values.yaml for the full shape. `backendRefs[].name` defaults to `<fullname>-es-http` and `backendRefs[].port` defaults to `9200`.

`backendTLSPolicy.caCertificateRef` controls which resource supplies the CA bundle. Defaults to `kind: Secret` with the ECK-generated `<fullname>-es-http-certs-public`. Override with `kind: ConfigMap` for Gateway implementations that only honor the Gateway API Core (ConfigMap-only) contract.

<br/>

### `serviceMonitor`

| Key | Default | Description |
|---|---|---|
| `enabled` | `false` | Render a ServiceMonitor. |
| `namespace` | `""` | Defaults to Release.Namespace. |
| `releaseLabel` | `""` | Prometheus Operator release label. |
| `interval` / `scrapeTimeout` | `30s` / `10s` | Scrape cadence. |
| `selector` | _(ES cluster-name matcher)_ | Override if using a custom exporter. |
| `endpoints` | `[]` | Empty → minimal HTTPS scrape of `/_prometheus/metrics` on port 9200 using `elastic` basic-auth. |

<br/>

### Other optional resources

| Block | Flag | Notes |
|---|---|---|
| `serviceAccount.create` | `false` | Render a dedicated ServiceAccount; auto-wired via `serviceAccountName`. Useful for IRSA / Workload Identity. |
| `ingress.enabled` | `false` | Legacy `networking.k8s.io/v1` Ingress. Prefer `httproute` on new clusters. |
| `networkPolicy.enabled` | `false` | `networking.k8s.io/v1` NetworkPolicy. Full ingress/egress rule arrays exposed. |
| `referenceGrants[]` | `[]` | List of Gateway API ReferenceGrants for cross-namespace Service/Secret access. |

<br/>

## Maintaining this chart

### Bumping the Elasticsearch version

```bash
cd charts/elasticsearch-eck
./upgrade.sh --dry-run          # preview
./upgrade.sh                    # bump to latest GA
./upgrade.sh --version 9.1.2    # pin to a specific version
./upgrade.sh --rollback         # restore files from backup/
```

`upgrade.sh` updates `Chart.yaml` `appVersion` and `values.yaml` `version`; it does NOT bump the chart's own SemVer or touch any cluster. After reviewing the diff:

```bash
make bump CHART=elasticsearch-eck LEVEL=minor
make lint CHART=elasticsearch-eck
make template CHART=elasticsearch-eck
```

<br/>

## License

Apache-2.0. See [LICENSE](../../LICENSE).
