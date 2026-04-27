# redis

Standalone single-node Redis chart — Deployment + PVC + Service, with optional Secret (auth password), optional ConfigMap (`redis.conf`), NetworkPolicy, ServiceAccount and chart-managed image pull Secret. Designed for dev / staging / single-replica caches and **in-place migration off legacy raw-YAML deployments** (existingClaim, existingSecret, fullnameOverride, custom mountPath).

For HA prefer Sentinel / Cluster topology — out of scope.

> Looking for Redis-API compatible without Redis Source-Available License v2 / SSPL exposure? See the sibling chart `valkey-cr`.

<br/>

## What it deploys

| Resource | Always rendered | Notes |
|---|---|---|
| `Deployment` | yes | single replica, `Recreate` strategy |
| `Service` | yes | `ClusterIP` default, `NodePort` opt-in |
| `PersistentVolumeClaim` | when `persistence.enabled` is true and `persistence.existingClaim` is empty | mounted at `persistence.mountPath` (default `/data`) |
| `Secret` | when `auth.enabled` is true and `auth.existingSecret` is empty | holds the Redis password under `auth.passwordKey` |
| `ConfigMap` | when `customConfig` is non-empty | `redis.conf` mounted at `/etc/redis`, container starts with `redis-server /etc/redis/redis.conf` |
| `Secret` (dockerconfigjson) | when `imagePullSecret.create` is true | additive to `imagePullSecrets[]` |
| `ServiceAccount` | when `serviceAccount.create` is true | scope-pinned IRSA / pull Secrets |
| `NetworkPolicy` | when `networkPolicy.enabled` is true | native `networking.k8s.io/v1` shape |

No backup CronJob — Redis is typically a cache, and its canonical persistence (RDB / AOF) lives on the same volume. For offsite backups run a sidecar that uploads RDB to object storage.

<br/>

## Prerequisites

- Kubernetes >= 1.25
- A StorageClass for the data PVC (or supply `persistence.existingClaim`)

<br/>

## Install

### OCI registry (Helm 3.8+)

```bash
helm install dev-redis oci://ghcr.io/somaz94/charts/redis --version 0.1.0 \
  --namespace projectm-db-redis --create-namespace
```

### Classic Helm repo

```bash
helm repo add somaz94 https://charts.somaz.blog
helm install dev-redis somaz94/redis --version 0.1.0 \
  --namespace projectm-db-redis --create-namespace \
  -f my-values.yaml
```

<br/>

## Quick examples

<br/>

### 1. Default — no auth, default config, chart-managed PVC (dev cache)

```yaml
persistence:
  size: 5Gi
service:
  type: ClusterIP
```

<br/>

### 2. Auth enabled + tuned config

```yaml
auth:
  enabled: true
  password: changeme
customConfig: |
  maxmemory 1gb
  maxmemory-policy allkeys-lru
  appendonly yes
  appendfsync everysec
  tcp-keepalive 60
service:
  type: NodePort
  nodePort: 30490
```

<br/>

### 3. Adopt a pre-existing raw-YAML deployment in place (no data movement)

The legacy raw-YAML for `dev-projectm-redis` mounted the PVC at `/redis-master-data` rather than the standard `/data`. The chart's `persistence.mountPath` lets you preserve that mount layout so Redis finds its existing RDB / AOF files.

```yaml
fullnameOverride: dev-projectm-redis

persistence:
  existingClaim: dev-projectm-redis-pvc
  mountPath: /redis-master-data        # legacy raw-YAML path

service:
  type: NodePort
  nodePort: 30479

imagePullSecrets:
  - name: harbor-robot-secret
```

Adoption checklist before `helm upgrade --install`:

```bash
KCTX=<your-context>
NS=projectm-db-redis

# 1. Annotate existing resources for Helm ownership
for kind in pvc/dev-projectm-redis-pvc service/dev-projectm-redis; do
  kubectl --context $KCTX -n $NS annotate "$kind" \
    meta.helm.sh/release-name=dev-projectm-redis \
    meta.helm.sh/release-namespace=$NS --overwrite
  kubectl --context $KCTX -n $NS label "$kind" \
    app.kubernetes.io/managed-by=Helm --overwrite
done

# 2. (Optional) belt-and-suspenders against accidental future helm uninstall
kubectl --context $KCTX -n $NS annotate pvc dev-projectm-redis-pvc \
  helm.sh/resource-policy=keep --overwrite

# 3. Drop the legacy Deployment so Helm can recreate with new selector
kubectl --context $KCTX -n $NS delete deployment dev-projectm-redis --wait

# 4. helm install. After install, remove stale `app:` key from Service
#    selector that helm's client-side merge left behind:
kubectl --context $KCTX -n $NS patch svc dev-projectm-redis \
  --type=json -p='[{"op":"remove","path":"/spec/selector/app"}]'
```

<br/>

### 4. Reuse a pre-existing auth Secret with a non-standard key

```yaml
auth:
  enabled: true
  existingSecret: app-shared-redis-creds
  passwordKey: REDIS_AUTH_TOKEN          # legacy key name in the existing Secret
```

<br/>

### 5. Private registry — chart-managed pull Secret

```yaml
imagePullSecret:
  create: true
  dockerconfigjson: <base64 ~/.docker/config.json>
image:
  repository: harbor.example.com/library/redis
  tag: "7.4-alpine"
```

<br/>

## Values reference

<br/>

### Naming + adoption

| Key | Default | Description |
|---|---|---|
| `nameOverride` | `""` | overrides `app.kubernetes.io/name` label |
| `fullnameOverride` | `""` | overrides the base name for Deployment / Service / default PVC / default Secret / default ConfigMap |
| `configMap.nameOverride` | `""` | overrides only the ConfigMap name (default `<fullname>-config`) |

<br/>

### Image

| Key | Default | Description |
|---|---|---|
| `image.repository` | `redis` | container image repository |
| `image.tag` | `""` (= `Chart.AppVersion`, currently `8.2-alpine`) | tag override. NOTE: Redis 7.5+ is licensed under RSALv2 / SSPL (not OSI-approved). Pin to `7.4-alpine` to stay on the last BSD-licensed Redis. The chart itself is Apache-2.0. |
| `image.pullPolicy` | `IfNotPresent` | |
| `imagePullSecrets[]` | `[]` | bring-your-own pull Secrets, additive |
| `imagePullSecret.create` | `false` | render a `dockerconfigjson` Secret |
| `imagePullSecret.name` | `""` (= `<fullname>-pull-secret`) | name override |
| `imagePullSecret.dockerconfigjson` | `""` | base64-encoded `~/.docker/config.json` |

<br/>

### Service

| Key | Default | Description |
|---|---|---|
| `service.type` | `ClusterIP` | one of `ClusterIP` / `NodePort` / `LoadBalancer` |
| `service.port` | `6379` | |
| `service.nodePort` | `null` | required when `service.type=NodePort` and you want a fixed port |
| `service.annotations` | `{}` | merged with `commonAnnotations` |

<br/>

### Persistence

| Key | Default | Description |
|---|---|---|
| `persistence.enabled` | `true` | when false, mounts an `emptyDir` (cache-only mode) |
| `persistence.storageClass` | `""` | empty = cluster default |
| `persistence.accessModes` | `[ReadWriteOnce]` | |
| `persistence.size` | `5Gi` | |
| `persistence.existingClaim` | `""` | when set, chart skips PVC rendering and the Pod mounts this PVC |
| `persistence.annotations` | `{}` | merged with `commonAnnotations` |
| `persistence.mountPath` | `/data` | mount path inside the Redis container |

<br/>

### Authentication

| Key | Default | Description |
|---|---|---|
| `auth.enabled` | `false` | toggle `requirepass` |
| `auth.password` | `""` | required when `auth.enabled` is true and `existingSecret` is empty |
| `auth.existingSecret` | `""` | when set, chart skips Secret rendering |
| `auth.passwordKey` | `redis-password` | secret key the container reads `REDIS_PASSWORD` from |

<br/>

### Configuration

| Key | Default | Description |
|---|---|---|
| `customConfig` | `""` | when non-empty, rendered into a ConfigMap as `redis.conf` and mounted at `/etc/redis`. Container starts with `redis-server /etc/redis/redis.conf`. When empty, the container runs the image's default config. |

When both `customConfig` and `auth.enabled` are set, the container is started with `--requirepass $(REDIS_PASSWORD)` appended after the config-file argument so the env-injected password takes precedence over any inline `requirepass` directive in `customConfig`. The password value is sourced from the Secret at runtime — never written to the rendered ConfigMap.

<br/>

### Pod scheduling + resources

| Key | Default | Description |
|---|---|---|
| `resources.requests.cpu` | `100m` | |
| `resources.requests.memory` | `256Mi` | |
| `resources.limits.cpu` | `500m` | |
| `resources.limits.memory` | `1Gi` | |
| `nodeSelector` / `tolerations` / `affinity` / `topologySpreadConstraints` / `priorityClassName` | empty | standard pod scheduling knobs |
| `podSecurityContext` / `securityContext` | `{}` | |
| `livenessProbe` / `readinessProbe` | TCP probe on `redis` port | safe to leave on by default |

<br/>

### Escape hatches

| Key | Default | Description |
|---|---|---|
| `commonLabels` / `commonAnnotations` | `{}` | applied to every resource |
| `resourceMetadata.<resource>.{labels,annotations}` | `{}` | per-resource override |
| `specExtra` | `{}` | merged into `Deployment.spec` |
| `podTemplateExtra` | `{}` | merged into `PodTemplateSpec.spec` |
| `kubernetesExtra` | `{}` | each value rendered as an additional manifest in this release |
| `serviceAccount.{create,name,annotations,imagePullSecrets,automountServiceAccountToken}` | `create=false` | scope-pinned SA |
| `networkPolicy.{enabled,policyTypes,ingress,egress,podSelector}` | `enabled=false` | native `networking.k8s.io/v1` shape |

<br/>

## License

[Apache-2.0](../../LICENSE)
