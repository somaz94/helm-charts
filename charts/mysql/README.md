# mysql

Standalone single-node MySQL 8 chart — Deployment + ConfigMap + Secret + PVC + Service, optional backup CronJob, NetworkPolicy, ServiceAccount and chart-managed image pull Secret. Designed for dev / staging / single-replica installs and **in-place migration off legacy raw-YAML deployments** (existingClaim, existingSecret, fullnameOverride, custom secret-key names).

For HA prefer an external managed DB (RDS / CloudSQL / Vitess) — out of scope.

<br/>

## What it deploys

| Resource | Always rendered | Notes |
|---|---|---|
| `Deployment` | yes | single replica, `Recreate` strategy |
| `Service` | yes | `ClusterIP` default, `NodePort` opt-in |
| `ConfigMap` | yes | `custom.cnf` mounted at `/etc/mysql/conf.d` |
| `Secret` | when `auth.existingSecret` is empty | renders `MYSQL_*` keys (key names configurable) |
| `PersistentVolumeClaim` | when `persistence.enabled` is true and `persistence.existingClaim` is empty | `/var/lib/mysql` |
| `Secret` (dockerconfigjson) | when `imagePullSecret.create` is true | additive to `imagePullSecrets[]` |
| `ServiceAccount` | when `serviceAccount.create` is true | scope-pinned IRSA / pull Secrets |
| `NetworkPolicy` | when `networkPolicy.enabled` is true | native `networking.k8s.io/v1` shape |
| `CronJob` + backup `PersistentVolumeClaim` | when `backup.enabled` is true | daily `mysqldump`, configurable retention |

<br/>

## Prerequisites

- Kubernetes >= 1.25
- A StorageClass for the data PVC (or supply `persistence.existingClaim`)
- For NFS-backed storage: append the NFS-safe options below to `customConfig`

<br/>

## Install

### OCI registry (Helm 3.8+)

```bash
helm install projectm-db oci://ghcr.io/somaz94/charts/mysql --version 0.1.0 \
  --namespace projectm-db-redis --create-namespace \
  --set auth.user=projectm \
  --set auth.password='<password>' \
  --set auth.rootPassword='<root-password>'
```

### Classic Helm repo

```bash
helm repo add somaz94 https://charts.somaz.blog
helm install projectm-db somaz94/mysql --version 0.1.0 \
  --namespace projectm-db-redis --create-namespace \
  -f my-values.yaml
```

<br/>

## Quick examples

<br/>

### 1. Default — chart-managed Secret + chart-managed PVC

```yaml
auth:
  user: projectm
  password: changeme
  database: projectm
  rootPassword: changeme-root
persistence:
  size: 20Gi
service:
  type: ClusterIP
```

<br/>

### 2. NodePort + chart-managed Secret + dev-tuned config

```yaml
auth:
  user: projectm
  password: changeme
  rootPassword: changeme-root
service:
  type: NodePort
  nodePort: 30636
customConfig: |
  [mysqld]
  character-set-server=utf8mb4
  max_connections=5000
  innodb_buffer_pool_size=1G
  innodb_use_native_aio=0      # NFS
  innodb_flush_method=fsync    # NFS
  skip_external_locking=1      # NFS
```

<br/>

### 3. Adopt a pre-existing raw-YAML deployment in place (no data movement)

This pattern lets you migrate a legacy `kubectl apply -f db.yaml` install to Helm management without restoring from backup. Existing PVC, Secret and ConfigMap are reused; the chart only takes ownership of the Deployment and Service.

```yaml
# Force the Helm-rendered resources to use the legacy names.
fullnameOverride: projectm-db
configMap:
  nameOverride: projectm-db-config

# Reuse the legacy Secret. Original keys were `DB_USERNAME` / `DB_PASSWORD` /
# `DB_ROOT_PASSWORD` — different from the chart's `MYSQL_*` defaults. Tell the
# chart which secret keys to read from; env var names on the container stay
# the same (MYSQL_USER, MYSQL_PASSWORD, MYSQL_ROOT_PASSWORD).
auth:
  existingSecret: projectm-db-secret
  secretKeys:
    user: DB_USERNAME
    password: DB_PASSWORD
    rootPassword: DB_ROOT_PASSWORD

# Reuse the legacy PVC — chart will not render a new PVC.
persistence:
  existingClaim: projectm-db-pvc

# Preserve the legacy NodePort so external clients keep working.
service:
  type: NodePort
  nodePort: 30636
```

Adoption checklist before `helm upgrade --install`:

```bash
# 1. Annotate existing resources so Helm accepts ownership
KCTX=<your-context>
NS=projectm-db-redis
for kind in pvc/projectm-db-pvc \
            secret/projectm-db-secret \
            configmap/projectm-db-config \
            service/projectm-db; do
  kubectl --context $KCTX -n $NS annotate "$kind" \
    meta.helm.sh/release-name=projectm-db \
    meta.helm.sh/release-namespace=$NS --overwrite
  kubectl --context $KCTX -n $NS label "$kind" \
    app.kubernetes.io/managed-by=Helm --overwrite
done

# 2. (Optional) belt-and-suspenders against accidental future helm uninstall
kubectl --context $KCTX -n $NS annotate pvc projectm-db-pvc \
  helm.sh/resource-policy=keep --overwrite

# 3. Drop the legacy Deployment so Helm can recreate with new selector
#    (Deployment.spec.selector is immutable; ~30s downtime, PVC unaffected)
kubectl --context $KCTX -n $NS delete deployment projectm-db --wait

# 4. helm install. After install, remove stale `app:` key from Service
#    selector that helm's client-side merge left behind:
kubectl --context $KCTX -n $NS patch svc projectm-db \
  --type=json -p='[{"op":"remove","path":"/spec/selector/app"}]'
```

<br/>

### 4. Backup CronJob — daily mysqldump

```yaml
auth:
  user: projectm
  password: changeme
  database: projectm
  rootPassword: changeme-root
backup:
  enabled: true
  schedule: "0 18 * * *"        # 03:00 KST = 18:00 UTC
  retentionDays: 30
  persistence:
    enabled: true
    storageClass: nfs-client
    size: 50Gi
```

When `auth.database` is set, the CronJob runs `mysqldump <db>` with the user credential. When empty, it runs `mysqldump --all-databases` with the root credential. Backups are written to `/backup-data/mysql-<db|all>-<YYYYMMDD>.sql`; files older than `retentionDays` are pruned each run.

Trigger an ad-hoc run:

```bash
kubectl -n projectm-db-redis create job \
  --from=cronjob/projectm-db-backup projectm-db-backup-manual-$(date +%Y%m%d-%H%M)
```

<br/>

### 5. Private registry — chart-managed pull Secret

```yaml
imagePullSecret:
  create: true
  dockerconfigjson: <base64 ~/.docker/config.json>
image:
  repository: harbor.example.com/library/mysql
  tag: "8.0.43"
```

Generate the `dockerconfigjson` value:

```bash
docker login harbor.example.com
cat ~/.docker/config.json | base64
# OR
kubectl create secret docker-registry tmp \
  --docker-server=harbor.example.com \
  --docker-username=robot$ci \
  --docker-password='<token>' \
  --dry-run=client -o jsonpath='{.data.\.dockerconfigjson}'
```

The chart-managed Secret is **additive** to `imagePullSecrets[]` — set both for layered fallback (e.g. a BYOIPS backup credential alongside a chart-rendered primary).

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
| `image.repository` | `mysql` | container image repository |
| `image.tag` | `""` (= `Chart.AppVersion`, currently `8.0.43`) | tag override |
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
| `service.port` | `3306` | |
| `service.nodePort` | `null` | required when `service.type=NodePort` and you want a fixed port |
| `service.annotations` | `{}` | merged with `commonAnnotations` |

<br/>

### Persistence

| Key | Default | Description |
|---|---|---|
| `persistence.enabled` | `true` | when false, mounts an `emptyDir` for `/var/lib/mysql` (dev only) |
| `persistence.storageClass` | `""` | empty = cluster default |
| `persistence.accessModes` | `[ReadWriteOnce]` | |
| `persistence.size` | `20Gi` | |
| `persistence.existingClaim` | `""` | when set, chart skips PVC rendering and the Pod mounts this PVC |
| `persistence.annotations` | `{}` | merged with `commonAnnotations` |

<br/>

### Authentication

| Key | Default | Description |
|---|---|---|
| `auth.user` | `""` | required when `existingSecret` is empty |
| `auth.password` | `""` | required when `existingSecret` is empty |
| `auth.database` | `""` | optional — when empty, `MYSQL_DATABASE` env not injected |
| `auth.rootPassword` | `""` | required when `existingSecret` is empty |
| `auth.existingSecret` | `""` | when set, chart skips Secret rendering |
| `auth.secretKeys.user` | `MYSQL_USER` | secret key the container reads `MYSQL_USER` from |
| `auth.secretKeys.password` | `MYSQL_PASSWORD` | secret key for `MYSQL_PASSWORD` |
| `auth.secretKeys.rootPassword` | `MYSQL_ROOT_PASSWORD` | secret key for `MYSQL_ROOT_PASSWORD` |
| `auth.secretKeys.database` | `MYSQL_DATABASE` | secret key for `MYSQL_DATABASE` (only used when `auth.database` is set) |

<br/>

### Pod scheduling + resources

| Key | Default | Description |
|---|---|---|
| `resources.requests.cpu` | `100m` | |
| `resources.requests.memory` | `256Mi` | |
| `resources.limits.cpu` | `1000m` | |
| `resources.limits.memory` | `2Gi` | |
| `nodeSelector` / `tolerations` / `affinity` / `topologySpreadConstraints` / `priorityClassName` | empty | standard pod scheduling knobs |
| `podSecurityContext` / `securityContext` | `{}` | |
| `livenessProbe` / `readinessProbe` | `{}` | empty by default to avoid initdb race; enable after first install |

<br/>

### Backup CronJob

| Key | Default | Description |
|---|---|---|
| `backup.enabled` | `false` | |
| `backup.schedule` | `"0 18 * * *"` | cron in cluster timezone |
| `backup.concurrencyPolicy` | `Forbid` | |
| `backup.successfulJobsHistoryLimit` | `3` | |
| `backup.failedJobsHistoryLimit` | `3` | |
| `backup.retentionDays` | `30` | files older than this are pruned |
| `backup.image.{repository,tag,pullPolicy}` | inherits from `image.*` when empty | override to pin a different mysqldump client image |
| `backup.resources` | `{}` | |
| `backup.persistence.*` | RWO 20Gi | dedicated PVC for backups |

<br/>

### Escape hatches

| Key | Default | Description |
|---|---|---|
| `customConfig` | tuned generic `[mysqld]` | rendered into ConfigMap → mounted as `/etc/mysql/conf.d/custom.cnf` |
| `commonLabels` / `commonAnnotations` | `{}` | applied to every resource |
| `resourceMetadata.<resource>.{labels,annotations}` | `{}` | per-resource override |
| `specExtra` | `{}` | merged into `Deployment.spec` |
| `podTemplateExtra` | `{}` | merged into `PodTemplateSpec.spec` |
| `kubernetesExtra` | `{}` | each value rendered as an additional manifest in this release |
| `serviceAccount.{create,name,annotations,imagePullSecrets,automountServiceAccountToken}` | `create=false` | scope-pinned SA |
| `networkPolicy.{enabled,policyTypes,ingress,egress,podSelector}` | `enabled=false` | native `networking.k8s.io/v1` shape |

<br/>

## NFS notes

NFS-backed PVCs require three options to avoid InnoDB lock errors and `O_DIRECT` failures. Append to `customConfig`:

```yaml
customConfig: |
  [mysqld]
  innodb_use_native_aio=0
  innodb_flush_method=fsync
  skip_external_locking=1
  # ... rest of your config
```

<br/>

## License

[Apache-2.0](../../LICENSE)
