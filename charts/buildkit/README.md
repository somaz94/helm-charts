# buildkit

Standalone BuildKit StatefulSet — `moby/buildkit` pod (rootful, privileged) with optional registry CA-bundle Secret + optional `buildkitd.toml` ConfigMap, cache PVC via `volumeClaimTemplates`, ClusterIP Service on TCP 1234. Designed for in-cluster `docker buildx` consumers (kubernetes driver or remote driver).

The headline use case is **multi-arch builds against a self-signed registry**: ephemeral buildx buildkit containers can only thread `insecure = true` to the registry endpoint, not the OAuth token endpoint, so an `image FROM` against the self-signed registry fails to verify. A standalone BuildKit StatefulSet with the registry CA baked into its trust store sidesteps that limit cleanly.

<br/>

## What it deploys

| Resource | Always rendered | Notes |
|---|---|---|
| `StatefulSet` | yes | `replicaCount` (default 1), `RollingUpdate` strategy |
| `Service` | yes | `ClusterIP` default, port 1234 |
| `PersistentVolumeClaim` (per replica, via `volumeClaimTemplates`) | when `persistence.enabled` is true | mounted at `persistence.mountPath` (default `/var/lib/buildkit`) |
| `Secret` (CA bundle) | when `registry.caBundle.enabled` is true and `existingSecret` is empty | holds the PEM bytes under `registry.caBundle.key` |
| `ConfigMap` (`buildkitd.toml`) | when `buildkitdConfig` is non-empty **OR** `registry.caBundle.enabled` is true | mounted at `/etc/buildkit`, container starts with `--config /etc/buildkit/buildkitd.toml` |
| `Secret` (dockerconfigjson) | when `imagePullSecret.create` is true | additive to `imagePullSecrets[]` |
| `ServiceAccount` | when `serviceAccount.create` is true | scope-pinned IRSA / pull Secrets |
| `NetworkPolicy` | when `networkPolicy.enabled` is true | native `networking.k8s.io/v1` shape |

No backup CronJob — the cache PVC is rebuildable, not authoritative state.

<br/>

## Versioning

- Chart `version` — this chart's own SemVer, bumped on every change.
- `appVersion` — the `moby/buildkit` release the chart targets; `image.tag` defaults to it when left empty. Upstream publishes only `v`-prefixed image tags, so `appVersion` carries the `v` as well.
- Bumped by [`upgrade.sh`](upgrade.sh), which tracks `moby/buildkit` GitHub releases. See [Maintaining this chart](#maintaining-this-chart).

<br/>

## Prerequisites

- Kubernetes >= 1.25
- A StorageClass for the cache PVC (each replica gets one via `volumeClaimTemplates`)
- Privileged pod admission allowed in the target namespace (default `securityContext.privileged: true`)

<br/>

## Install

These snippets install the latest published chart. To pin an exact chart version, add `--version <x.y.z>` — released versions are the GitHub Release tags named `buildkit-<version>`.

<br/>

### OCI registry (Helm 3.8+)

```bash
helm install dev-buildkit oci://ghcr.io/somaz94/charts/buildkit \
  --namespace gitlab-runner --create-namespace
```

<br/>

### Classic Helm repo

```bash
helm repo add somaz94 https://charts.somaz.blog
helm install dev-buildkit somaz94/buildkit \
  --namespace gitlab-runner --create-namespace \
  -f my-values.yaml
```

<br/>

## Quick examples

<br/>

### 1. Default — single replica, default config, cache PVC

```yaml
replicaCount: 1
persistence:
  size: 20Gi
service:
  type: ClusterIP
```

<br/>

### 2. Self-signed registry — bake CA into the BuildKit trust store

The chart auto-renders a minimal `buildkitd.toml` that wires the mounted CA to the registry host. Drop the PEM into `registry.caBundle.ca` (Helm `--set-file` is the typical entrypoint):

```yaml
registry:
  caBundle:
    enabled: true
    host: harbor.example.com
    ca: |
      -----BEGIN CERTIFICATE-----
      MIID...
      -----END CERTIFICATE-----
```

Or reuse an existing Secret (e.g. one replicated from the registry's namespace via ExternalSecret):

```yaml
registry:
  caBundle:
    enabled: true
    existingSecret: harbor-ca-buildkit
    key: ca.crt                  # key name inside the Secret
    host: harbor.example.com
```

<br/>

### 3. Tuned `buildkitd.toml` (custom GC, multi-registry trust)

When `buildkitdConfig` is non-empty it wins outright; pair with `registry.caBundle.enabled: true` if you also need the CA file mounted:

```yaml
registry:
  caBundle:
    enabled: true
    existingSecret: harbor-ca-buildkit
    key: ca.crt
    host: harbor.example.com     # only used by auto-render; ignored when buildkitdConfig is set

buildkitdConfig: |
  [log]
    level = "info"                # error | warn | info | debug | trace

  [worker.oci]
    max-parallelism = 4
    gc = true
    gckeepstorage = 10000

  [registry."harbor.example.com"]
    ca = ["/etc/buildkit/certs/ca.crt"]

  [registry."ghcr.io"]
    mirrors = ["harbor.example.com/proxy/ghcr"]
```

<br/>

### 4. Two replicas + topology spread (lightweight HA)

```yaml
replicaCount: 2
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: kubernetes.io/hostname
    whenUnsatisfiable: ScheduleAnyway
    labelSelector:
      matchLabels:
        app.kubernetes.io/name: buildkit
        app.kubernetes.io/instance: dev-buildkit
```

<br/>

### 5. Remote driver consumer — direct TCP to the BuildKit Service

```bash
docker buildx create --driver remote \
  --name dev-buildkit \
  tcp://dev-buildkit.gitlab-runner.svc.cluster.local:1234

docker buildx build --builder dev-buildkit \
  --platform linux/amd64,linux/arm64 \
  --push -t harbor.example.com/toolchain/foo:tag .
```

The default rootful BuildKit listener has no auth — restrict the Service via NetworkPolicy or front it with mTLS (see upstream docs for `--tlscacert`/`--tlscert`/`--tlskey`).

<br/>

## Values reference

The tables below mirror [`values.yaml`](values.yaml), which is authoritative; [`values.schema.json`](values.schema.json) enforces the shape.

<br/>

### Naming + adoption

| Key | Default | Description |
|---|---|---|
| `nameOverride` | `""` | overrides `app.kubernetes.io/name` label |
| `fullnameOverride` | `""` | overrides the base name for StatefulSet / Service / default ConfigMap / default Secret |
| `serviceName` | `""` (= fullname) | StatefulSet `serviceName` — must match the Service name |
| `configMap.nameOverride` | `""` | overrides only the ConfigMap name (default `<fullname>-config`) |

<br/>

### Image

| Key | Default | Description |
|---|---|---|
| `image.repository` | `moby/buildkit` | container image repository |
| `image.tag` | `""` (= `Chart.AppVersion`) | tag override |
| `image.pullPolicy` | `IfNotPresent` | |
| `imagePullSecrets[]` | `[]` | bring-your-own pull Secrets, additive |
| `imagePullSecret.create` | `false` | render a `dockerconfigjson` Secret |
| `imagePullSecret.name` | `""` (= `<fullname>-pull-secret`) | name override |
| `imagePullSecret.dockerconfigjson` | `""` | base64-encoded `~/.docker/config.json` |

<br/>

### StatefulSet

| Key | Default | Description |
|---|---|---|
| `replicaCount` | `1` | |
| `updateStrategy.type` | `RollingUpdate` | one of `RollingUpdate` / `OnDelete` |

<br/>

### Service

| Key | Default | Description |
|---|---|---|
| `service.type` | `ClusterIP` | one of `ClusterIP` / `NodePort` / `LoadBalancer` |
| `service.port` | `1234` | |
| `service.nodePort` | `null` | required when `service.type=NodePort` and you want a fixed port |
| `service.annotations` | `{}` | merged with `commonAnnotations` |

<br/>

### Persistence

| Key | Default | Description |
|---|---|---|
| `persistence.enabled` | `true` | when false, mounts an `emptyDir` (no cache reuse across pod restarts) |
| `persistence.storageClass` | `""` | empty = cluster default |
| `persistence.accessModes` | `[ReadWriteOnce]` | |
| `persistence.size` | `20Gi` | |
| `persistence.annotations` | `{}` | merged with `commonAnnotations` |
| `persistence.mountPath` | `/var/lib/buildkit` | mount path inside the buildkitd container |

`volumeClaimTemplates`-style — each replica gets its own PVC named `cache-<sts-name>-<ordinal>`. PVCs are not deleted on `helm uninstall` by default.

<br/>

### Registry trust (CA bundle)

| Key | Default | Description |
|---|---|---|
| `registry.caBundle.enabled` | `false` | mount a CA file into the pod and (when `buildkitdConfig` is empty) auto-wire `registry."<host>".ca` in `buildkitd.toml` |
| `registry.caBundle.existingSecret` | `""` | when set, chart skips Secret rendering and mounts the given Secret |
| `registry.caBundle.key` | `ca.crt` | key inside the Secret holding the PEM bytes |
| `registry.caBundle.host` | `""` | registry FQDN — used by the auto-rendered `buildkitd.toml` and to label the Secret |
| `registry.caBundle.ca` | `""` | inline PEM bytes; required when `enabled=true` and `existingSecret` is empty |
| `registry.caBundle.caPath` | `/etc/buildkit/certs/ca.crt` | mount path inside the pod |
| `registry.caBundle.installToTrustStore` | `false` | when true (with `enabled=true`), an init container concatenates the base image's `/etc/ssl/certs/ca-certificates.crt` with the supplied CA into an emptyDir volume, and the main container's `SSL_CERT_FILE` env points at it. **Required for self-signed registries with OAuth token auth** — BuildKit's OAuth call uses the OS trust store, not `buildkitd.toml`'s `[registry.<host>].ca`. |
| `registry.caBundle.initContainerImage` | `""` (= main image) | override init container image repository |
| `registry.caBundle.initContainerImageTag` | `""` (= main image tag) | override init container image tag |
| `registry.caBundle.trustBundlePath` | `/etc/ssl/certs-merged/ca-certificates.crt` | mount path of the merged bundle inside the main container; also exposed as `SSL_CERT_FILE` |
| `registry.caBundle.systemTrustStorePath` | `/etc/ssl/certs/ca-certificates.crt` | absolute path inside the main container that the merged bundle subPath-mounts on top of, overlaying the OS default trust store. Set to `""` to disable the overlay (only env-var + directory mount remain). |

When does `installToTrustStore: true` matter? Two endpoints have different verification paths:

| Endpoint | What buildkit uses | Effect of `[registry.<host>].ca` | Effect of `SSL_CERT_FILE` env | Effect of system trust store overlay |
|---|---|---|---|---|
| Registry pull/push (`<host>/v2/...`) | `buildkitd.toml` registry config | trusted | trusted | trusted |
| OAuth token (`<host>/service/token`) | containerd resolver, OS trust store | **NOT used** | **NOT used** | **trusted** |

For Harbor (token-auth), only the **system trust store overlay** path lets BuildKit verify the OAuth endpoint. The env var alone is insufficient because containerd's docker resolver hardcodes the OS bundle path and ignores `SSL_CERT_FILE`. The chart's default `systemTrustStorePath: /etc/ssl/certs/ca-certificates.crt` matches alpine's convention and works with the upstream `moby/buildkit` image.

<br/>

### Configuration

| Key | Default | Description |
|---|---|---|
| `buildkitdConfig` | `""` | when non-empty, rendered into a ConfigMap as `buildkitd.toml` and mounted at `/etc/buildkit`. Container starts with `--config /etc/buildkit/buildkitd.toml`. When empty AND `registry.caBundle.enabled` is true, the chart auto-renders a minimal config that wires the CA path. |

<br/>

### Listener

| Key | Default | Description |
|---|---|---|
| `listener.unixSocket` | `/run/buildkit/buildkitd.sock` | always-on unix socket (required by `docker buildx --driver kubernetes`) |
| `listener.tcp.enabled` | `true` | toggle the TCP listener (required by `docker buildx --driver remote`) |
| `listener.tcp.port` | `1234` | TCP listener port; the Service `targetPort` lines up with this |

<br/>

### Pod scheduling + resources

| Key | Default | Description |
|---|---|---|
| `resources.requests.cpu` | `500m` | |
| `resources.requests.memory` | `1Gi` | |
| `resources.limits.cpu` | `4` | |
| `resources.limits.memory` | `8Gi` | |
| `nodeSelector` / `tolerations` / `affinity` / `topologySpreadConstraints` / `priorityClassName` | empty | standard pod scheduling knobs |
| `podSecurityContext` | `{}` | |
| `securityContext` | `{ privileged: true }` | required for the OCI worker's cgroup mount under rootful |
| `livenessProbe` / `readinessProbe` | `buildctl debug workers` exec | confirms the worker is registered |

<br/>

### Escape hatches

| Key | Default | Description |
|---|---|---|
| `commonLabels` / `commonAnnotations` | `{}` | applied to every resource |
| `resourceMetadata.<resource>.{labels,annotations}` | `{}` | per-resource override |
| `specExtra` | `{}` | merged into `StatefulSet.spec` |
| `podTemplateExtra` | `{}` | merged into `PodTemplateSpec.spec` |
| `kubernetesExtra` | `{}` | each value rendered as an additional manifest in this release |
| `serviceAccount.{create,name,annotations,imagePullSecrets,automountServiceAccountToken}` | `create=false` | scope-pinned SA |
| `networkPolicy.{enabled,policyTypes,ingress,egress,podSelector}` | `enabled=false` | native `networking.k8s.io/v1` shape |

<br/>

## Maintaining this chart

<br/>

### Bumping the BuildKit version

```bash
cd charts/buildkit
./upgrade.sh --dry-run           # preview
./upgrade.sh                     # bump to latest
./upgrade.sh --version 0.33.0    # pin to a specific version (bare, no "v")
./upgrade.sh --rollback          # restore files from backup/
```

`upgrade.sh` updates `Chart.yaml` `appVersion` only — the image tag is derived
from `.Chart.AppVersion`, so `values.yaml` is left untouched. It does NOT bump
the chart's own SemVer or touch any cluster.

Upstream publishes the image as `moby/buildkit:v<x.y.z>`, so this chart's
`appVersion` carries the `v` too (`TAG_PREFIX="v"`). Version sources report bare
`x.y.z`, so pass `--version` bare — the script re-applies the prefix when it
writes.

After reviewing the diff:

```bash
make bump CHART=buildkit LEVEL=patch
make lint CHART=buildkit
make template CHART=buildkit
```

<br/>

## License

[Apache-2.0](../../LICENSE)
