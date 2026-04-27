# postgresql

Standalone single-node PostgreSQL chart — Deployment + ConfigMap (`postgresql.conf` + `pg_hba.conf`) + Secret + PVC + Service, optional backup CronJob, NetworkPolicy, ServiceAccount, log emptyDir for `logging_collector` workloads, and chart-managed image pull Secret. Designed for dev / staging / single-replica installs and **in-place migration off legacy raw-YAML deployments** (existingClaim, existingSecret, fullnameOverride, custom secret-key names).

For HA prefer an external managed DB (RDS / CloudSQL / Patroni) — out of scope.

<br/>

## What it deploys

| Resource | Always rendered | Notes |
|---|---|---|
| `Deployment` | yes | single replica, `Recreate` strategy |
| `Service` | yes | `ClusterIP` default, `NodePort` opt-in |
| `ConfigMap` | yes | `postgresql.conf` + `pg_hba.conf` mounted at `/etc/postgresql` |
| `Secret` | when `auth.existingSecret` is empty | renders `POSTGRES_USER` + `POSTGRES_PASSWORD` (key names configurable) |
| `PersistentVolumeClaim` | when `persistence.enabled` is true and `persistence.existingClaim` is empty | data dir = `pgData` (default `/var/lib/postgresql/data/pgdata`) |
| `Secret` (dockerconfigjson) | when `imagePullSecret.create` is true | additive to `imagePullSecrets[]` |
| `ServiceAccount` | when `serviceAccount.create` is true | scope-pinned IRSA / pull Secrets |
| `NetworkPolicy` | when `networkPolicy.enabled` is true | native `networking.k8s.io/v1` shape |
| `CronJob` + backup `PersistentVolumeClaim` | when `backup.enabled` is true | daily `pg_dump` (or `pg_dumpall` when `auth.database` is empty) + retention |

<br/>

## Prerequisites

- Kubernetes >= 1.25
- A StorageClass for the data PVC (or supply `persistence.existingClaim`)
- The PVC must be empty on first install (initdb writes to `pgData`). Migration paths reuse a fully populated PVC — see "Adoption" below.

<br/>

## Install

### OCI registry (Helm 3.8+)

```bash
helm install projectm-postgres oci://ghcr.io/somaz94/charts/postgresql --version 0.1.0 \
  --namespace projectm-db-redis --create-namespace \
  --set auth.user=projectm \
  --set auth.password='<password>' \
  --set auth.database=projectm
```

### Classic Helm repo

```bash
helm repo add somaz94 https://charts.somaz.blog
helm install projectm-postgres somaz94/postgresql --version 0.1.0 \
  --namespace projectm-db-redis --create-namespace \
  -f my-values.yaml
```

<br/>

## Quick examples

<br/>

### 1. Default — chart-managed Secret + PVC

```yaml
auth:
  user: projectm
  password: changeme
  database: projectm
persistence:
  size: 20Gi
service:
  type: ClusterIP
```

<br/>

### 2. NodePort + tuned config

```yaml
auth:
  user: projectm
  password: changeme
  database: projectm
service:
  type: NodePort
  nodePort: 30632
customConfig:
  postgresqlConf: |
    listen_addresses = '*'
    max_connections = 5000
    shared_buffers = 1GB
    effective_cache_size = 3GB
    log_min_duration_statement = 2000
    statement_timeout = 120000
  pgHbaConf: |
    local   all             all                                     trust
    host    all             all             0.0.0.0/0               md5
    host    all             all             ::0/0                   md5
```

<br/>

### 3. Adopt a pre-existing raw-YAML deployment in place (no data movement)

This pattern lets you migrate a legacy `kubectl apply -f db.yaml` install to Helm management without restoring from backup. Existing PVC, Secret and ConfigMap are reused; the chart only takes ownership of the Deployment and Service.

```yaml
fullnameOverride: projectm-postgresql-db
configMap:
  nameOverride: projectm-postgresql-db-config

# Reuse the legacy Secret. Original keys were `DB_USERNAME` / `POSTGRES_PASSWORD`
# (the legacy raw-YAML used POSTGRES_DB as a literal env value, not in the
# Secret — this chart matches that pattern: `auth.database` is rendered as a
# plain `value:` env, not a secretKeyRef).
auth:
  existingSecret: projectm-postgresql-db-secret
  secretKeys:
    user: DB_USERNAME
    password: POSTGRES_PASSWORD
  database: projectm

persistence:
  existingClaim: projectm-postgresql-db-pvc

service:
  type: NodePort
  nodePort: 30632

# When the legacy raw YAML used logging_collector=on with /var/log/postgresql.
logCollector:
  enabled: true
```

Adoption checklist before `helm upgrade --install`:

```bash
KCTX=<your-context>
NS=projectm-db-redis

# 1. Annotate existing resources for Helm ownership
for kind in pvc/projectm-postgresql-db-pvc \
            secret/projectm-postgresql-db-secret \
            configmap/projectm-postgresql-db-config \
            service/projectm-postgresql-db; do
  kubectl --context $KCTX -n $NS annotate "$kind" \
    meta.helm.sh/release-name=projectm-postgresql-db \
    meta.helm.sh/release-namespace=$NS --overwrite
  kubectl --context $KCTX -n $NS label "$kind" \
    app.kubernetes.io/managed-by=Helm --overwrite
done

# 2. (Optional) belt-and-suspenders against accidental future helm uninstall
kubectl --context $KCTX -n $NS annotate pvc projectm-postgresql-db-pvc \
  helm.sh/resource-policy=keep --overwrite

# 3. Drop the legacy Deployment so Helm can recreate with new selector
kubectl --context $KCTX -n $NS delete deployment projectm-postgresql-db --wait

# 4. helm install. After install, remove stale `app:` key from Service
#    selector that helm's client-side merge left behind:
kubectl --context $KCTX -n $NS patch svc projectm-postgresql-db \
  --type=json -p='[{"op":"remove","path":"/spec/selector/app"}]'
```

<br/>

### 4. Backup CronJob — daily pg_dump

```yaml
auth:
  user: projectm
  password: changeme
  database: projectm
backup:
  enabled: true
  schedule: "0 18 * * *"        # 03:00 KST = 18:00 UTC
  retentionDays: 30
  persistence:
    enabled: true
    storageClass: nfs-client
    size: 50Gi
```

When `auth.database` is set, the CronJob runs `pg_dump <db>`. When empty, it runs `pg_dumpall`. Backups are written to `/backup-data/postgres-<db|all>-<YYYYMMDD>.sql`; files older than `retentionDays` are pruned each run.

Trigger an ad-hoc run:

```bash
kubectl -n projectm-db-redis create job \
  --from=cronjob/projectm-postgresql-db-backup \
  projectm-postgresql-db-backup-manual-$(date +%Y%m%d-%H%M)
```

<br/>

### 5. Private registry — chart-managed pull Secret

```yaml
imagePullSecret:
  create: true
  dockerconfigjson: <base64 ~/.docker/config.json>
image:
  repository: harbor.example.com/library/postgres
  tag: "16-alpine"
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
| `image.repository` | `postgres` | container image repository |
| `image.tag` | `""` (= `Chart.AppVersion`, currently `18-alpine`) | tag override |
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
| `service.port` | `5432` | |
| `service.nodePort` | `null` | required when `service.type=NodePort` and you want a fixed port |
| `service.annotations` | `{}` | merged with `commonAnnotations` |

<br/>

### Persistence

| Key | Default | Description |
|---|---|---|
| `persistence.enabled` | `true` | when false, mounts an `emptyDir` for `/var/lib/postgresql/data` (dev only) |
| `persistence.storageClass` | `""` | empty = cluster default |
| `persistence.accessModes` | `[ReadWriteOnce]` | |
| `persistence.size` | `20Gi` | |
| `persistence.existingClaim` | `""` | when set, chart skips PVC rendering and the Pod mounts this PVC |
| `persistence.annotations` | `{}` | merged with `commonAnnotations` |
| `pgData` | `/var/lib/postgresql/data/pgdata` | `PGDATA` env — initdb writes here (subdir of volume mount avoids `lost+found` collision on some storageclasses) |

<br/>

### Authentication

| Key | Default | Description |
|---|---|---|
| `auth.user` | `""` | required when `existingSecret` is empty |
| `auth.password` | `""` | required when `existingSecret` is empty |
| `auth.database` | `""` | optional. When set, `POSTGRES_DB` env is rendered as a plain `value:` (not from Secret) — DB name is not sensitive |
| `auth.existingSecret` | `""` | when set, chart skips Secret rendering |
| `auth.secretKeys.user` | `POSTGRES_USER` | secret key the container reads `POSTGRES_USER` from |
| `auth.secretKeys.password` | `POSTGRES_PASSWORD` | secret key for `POSTGRES_PASSWORD` |

<br/>

### Postgres configuration

| Key | Default | Description |
|---|---|---|
| `customConfig.postgresqlConf` | tuned generic settings | rendered into ConfigMap as `postgresql.conf` |
| `customConfig.pgHbaConf` | local trust + md5 over IP | rendered into ConfigMap as `pg_hba.conf` |
| `useCustomConfig` | `true` | when true, container starts with `-c config_file=…` + `-c hba_file=…` pointing at the mounted ConfigMap |
| `logCollector.enabled` | `false` | mount an `emptyDir` for `logging_collector = on` log files |
| `logCollector.mountPath` | `/var/log/postgresql` | |

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
| `backup.image.{repository,tag,pullPolicy}` | inherits from `image.*` when empty | override to pin a different `pg_dump` client image |
| `backup.resources` | `{}` | |
| `backup.persistence.*` | RWO 20Gi | dedicated PVC for backups |

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
