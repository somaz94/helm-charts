# ghost

Helm chart for [Ghost](https://ghost.org/) — Node.js blogging platform — with optional bundled MySQL, backup CronJob, HTTPRoute (Gateway API) and Ingress. Geared for self-hosted blogs on Kubernetes with a single-release install.

## What it deploys

| Resource | API | Purpose |
|---|---|---|
| `Deployment` | `apps/v1` | Ghost app container (`ghost:<tag>`) with RWO PVC for `/var/lib/ghost/content` |
| `Service` | `v1` | ClusterIP by default; NodePort / LoadBalancer opt-in |
| `PersistentVolumeClaim` | `v1` | Ghost content volume |
| `Deployment` | `apps/v1` | Bundled MySQL 8.x (optional, `mysql.enabled`) with Recreate strategy |
| `Service` | `v1` | MySQL ClusterIP Service |
| `PersistentVolumeClaim` | `v1` | MySQL data volume |
| `ConfigMap` | `v1` | MySQL `/etc/mysql/conf.d/custom.cnf` |
| `Secret` | `v1` | DB credentials (rendered or externally supplied) |
| `CronJob` | `batch/v1` | Daily backup job (optional, `backup.enabled`) — `mysqldump` + content tarball |
| `PersistentVolumeClaim` | `v1` | Backup target volume |
| `HTTPRoute` | `gateway.networking.k8s.io/v1` | Gateway API ingress (optional, `httproute.enabled`) |
| `Ingress` | `networking.k8s.io/v1` | Legacy Ingress (optional, `ingress.enabled`) |
| `ClientSettingsPolicy` | `gateway.nginx.org/v1alpha1` | NGINX Gateway Fabric body-size policy (optional) |
| `ServiceMonitor` | `monitoring.coreos.com/v1` | Prometheus scrape config (optional) |
| `ServiceAccount` | `v1` | Dedicated SA for IRSA / image pull secret scoping (optional, `serviceAccount.create`) |
| `NetworkPolicy` | `networking.k8s.io/v1` | Pod-level ingress/egress lock-down (optional, `networkPolicy.enabled`) |

## Versioning

- Chart `version` — this chart's own SemVer, bumped on every change.
- `appVersion` — the Ghost upstream version the defaults target (`image.tag` default, e.g. `5.117.0-alpine`).

## Prerequisites

- Kubernetes **1.25+**
- A `StorageClass` that supports `ReadWriteOnce` (default is fine for most providers)
- For `httproute.enabled`: a Gateway API–compliant controller (e.g. NGINX Gateway Fabric, Envoy Gateway, Contour) with a ready `Gateway`
- For `nginxGatewayFabric.clientSettings.enabled`: **NGINX Gateway Fabric** specifically (its `gateway.nginx.org/v1alpha1` CRDs)
- For `ingress.enabled`: an Ingress controller (ingress-nginx, Traefik, cloud LBs)

## Install

### OCI registry (Helm 3.8+)

```bash
helm install blog oci://ghcr.io/somaz94/charts/ghost \
  --version 0.1.0 \
  --namespace blog --create-namespace \
  --set url=https://blog.example.com \
  --set mysql.auth.user=ghost \
  --set mysql.auth.password=CHANGE_ME \
  --set mysql.auth.database=ghost \
  --set mysql.auth.rootPassword=CHANGE_ME_ROOT
```

### Classic Helm repo

```bash
helm repo add somaz94 https://charts.somaz.blog
helm repo update
helm install blog somaz94/ghost --version 0.1.0 -f values.yaml
```

## Required values

The chart **fails at render time** unless you provide:

- `url` — Ghost's public URL (include scheme)
- `mysql.auth.{user,password,database,rootPassword}` — **when `mysql.enabled: true` (default)** and `mysql.auth.existingSecret` is empty
- `externalDatabase.{host,user,password,database}` — when `mysql.enabled: false` and `externalDatabase.existingSecret` is empty

## Examples

### Minimal (bundled MySQL, cluster-internal access only)

```yaml
url: https://blog.example.com
mysql:
  auth:
    user: ghost
    password: s3cret
    database: ghost
    rootPassword: s3cret-root
```

### External MySQL (no bundled DB)

```yaml
url: https://blog.example.com
mysql:
  enabled: false
externalDatabase:
  host: mysql.prod.example.com
  port: 3306
  database: ghost
  user: ghost
  existingSecret: ghost-db-creds   # keys: MYSQL_USER, MYSQL_PASSWORD, MYSQL_DATABASE
```

### Gateway API (HTTPRoute) with NGINX Gateway Fabric body-size policy

```yaml
url: https://blog.example.com
mysql:
  auth:
    user: ghost
    password: s3cret
    database: ghost
    rootPassword: s3cret-root
httproute:
  enabled: true
  parentRefs:
    - name: ngf
      namespace: nginx-gateway
  hostnames:
    - blog.example.com
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - {}                         # defaults to chart's own Service:port
nginxGatewayFabric:
  clientSettings:
    enabled: true
    bodyMaxSize: "500m"              # allow Ghost media uploads
uploads:
  maxFileSize: 524288000             # 500 MiB, mirrored into Ghost config
```

### Legacy Ingress (ingress-nginx)

```yaml
url: https://blog.example.com
mysql:
  auth:
    user: ghost
    password: s3cret
    database: ghost
    rootPassword: s3cret-root
ingress:
  enabled: true
  className: nginx
  host: blog.example.com
  annotations:
    nginx.ingress.kubernetes.io/proxy-body-size: "500m"
    cert-manager.io/cluster-issuer: letsencrypt-prod
  tls:
    - hosts: [blog.example.com]
      secretName: blog-tls
```

### Daily backup (MySQL dump + content tarball, 30-day retention)

```yaml
url: https://blog.example.com
mysql:
  auth: { user: ghost, password: s3cret, database: ghost, rootPassword: s3cret-root }
backup:
  enabled: true
  schedule: "0 18 * * *"          # 03:00 KST (UTC+9) = 18:00 UTC
  retentionDays: 30
  persistence:
    size: 20Gi
    storageClass: ""              # cluster default
```

Inspect or trigger manually:

```bash
kubectl -n blog get cronjob blog-ghost-backup
kubectl -n blog create job --from=cronjob/blog-ghost-backup manual-$(date +%s)
kubectl -n blog logs -l job-name=manual-...
```

### Pulling from a private registry (chart-managed Secret)

When the chart should also render the `kubernetes.io/dockerconfigjson` Secret (instead of you creating it ahead of time), set `imagePullSecret.create=true` and provide the base64-encoded `dockerconfigjson` blob. The Pod-level `imagePullSecrets` is then injected into Ghost, MySQL and the backup CronJob automatically; existing `imagePullSecrets[]` references (BYOIPS) are still honored and merged additively.

Generate `dockerconfigjson` once with either:

```bash
docker login registry.example.com && cat ~/.docker/config.json | base64

# or, without docker, build it via kubectl:
kubectl create secret docker-registry tmp \
  --docker-server=registry.example.com \
  --docker-username=robot \
  --docker-password=<token> \
  --dry-run=client -o jsonpath='{.data.\.dockerconfigjson}'
```

Then in your values:

```yaml
url: https://blog.example.com
image:
  repository: registry.example.com/library/ghost
  tag: 5.117.0-alpine
mysql:
  image:
    repository: registry.example.com/library/mysql
    tag: "8.0.40"
  auth: { user: ghost, password: s3cret, database: ghost, rootPassword: s3cret-root }

imagePullSecret:
  create: true
  dockerconfigjson: ewogICJhdXRoc...    # output from the command above
```

Or keep `imagePullSecret.create: false` and reference an externally-managed Secret:

```yaml
imagePullSecrets:
  - name: my-pull-secret
```

### Adopting pre-existing legacy resources

When migrating from a hand-rolled deployment whose MySQL resources do not follow the chart's default `<release>-mysql` naming, set `mysql.fullnameOverride` (and optionally `mysql.configMap.nameOverride`) so the chart targets the existing names. Combine with `existingClaim` / `existingSecret` so PVCs and the auth Secret are reused instead of recreated.

Pre-flight: stamp every adopted resource with the standard Helm ownership annotations and label so `helm install` does not fail on conflicts.

```bash
RELEASE=ghost
NS=blog
for kind in deployment/ghost-db service/ghost-db configmap/ghost-db-config secret/ghost-db-secret \
            pvc/ghost-content-pvc pvc/ghost-db-pvc pvc/ghost-backup-pvc; do
  kubectl -n "$NS" annotate "$kind" \
    meta.helm.sh/release-name="$RELEASE" \
    meta.helm.sh/release-namespace="$NS" --overwrite
  kubectl -n "$NS" label "$kind" \
    app.kubernetes.io/managed-by=Helm --overwrite
done
```

Values:

```yaml
url: https://blog.example.com

mysql:
  fullnameOverride: ghost-db          # Deployment + Service + (default) Secret base name
  configMap:
    nameOverride: ghost-db-config     # ConfigMap keeps its legacy `-config` suffix
  auth:
    existingSecret: ghost-db-secret   # reuse the existing credentials Secret as-is
  persistence:
    existingClaim: ghost-db-pvc       # bind to the existing MySQL PVC

persistence:
  existingClaim: ghost-content-pvc    # Ghost content PVC

backup:
  enabled: true
  persistence:
    existingClaim: ghost-backup-pvc   # backup PVC
```

Run `helm diff upgrade --install ...` first and confirm every resource shows up as a modify (not an add) before applying.

## NFS notes

Ghost on NFS-backed RWO volumes needs MySQL tuning. Append to `mysql.customConfig`:

```ini
innodb_use_native_aio=0      # NFS does not support native AIO
innodb_flush_method=fsync    # O_DIRECT → fsync for NFS stability
skip_external_locking=1      # disable external locking
```

Or replace the defaults entirely — the chart passes the full string verbatim into `/etc/mysql/conf.d/custom.cnf`.

## Values reference

See [`values.yaml`](values.yaml) for the fully commented defaults and [`values.schema.json`](values.schema.json) for JSON Schema validation.

Key blocks:

| Block | Purpose |
|---|---|
| `url` | Ghost's public URL (**required**) |
| `image.{repository,tag,pullPolicy}` | Ghost container image |
| `persistence.*` | Ghost content PVC (storageClass, size, accessModes, existingClaim) |
| `uploads.maxFileSize` | Ghost's `fileStorage__maxFileSize` env (bytes) |
| `env[]` | Extra env passed through (`mail__*`, `database__*`, etc.) |
| `mysql.*` | Bundled MySQL: image, auth, customConfig, persistence, resources |
| `externalDatabase.*` | Alternative to `mysql.*` when `mysql.enabled: false` |
| `backup.*` | CronJob schedule, retention, PVC |
| `httproute.*` / `ingress.*` | Two mutually compatible ingress paths |
| `nginxGatewayFabric.clientSettings.*` | NGF `ClientSettingsPolicy` body-size limit |
| `serviceMonitor.*` | Prometheus Operator scrape |
| `serviceAccount.*` | Optional dedicated SA (IRSA / Workload Identity / imagePullSecrets) |
| `networkPolicy.*` | Optional `NetworkPolicy` (native `ingress`/`egress` rules; deny-all when empty + `policyTypes` set) |
| `commonLabels` / `commonAnnotations` / `resourceMetadata.*` | Labels and annotations per resource kind |
| `specExtra` / `podTemplateExtra` / `kubernetesExtra` | Escape hatches (merge-in arbitrary fields) |

## Known limitations

- Single-replica Ghost with Recreate update strategy (PVC RWO). `helm upgrade` will incur short downtime — suitable for personal blogs, not highly-available production sites.
- Bundled MySQL is single-node with no replication. For production prefer an external managed DB (RDS, CloudSQL, DO Managed DB) with `mysql.enabled: false`.
- `helm upgrade` over an install that originally used plain YAML manifests requires PVC adoption (`kubectl annotate`/`label` the existing PVC with `meta.helm.sh/release-name` + `app.kubernetes.io/managed-by=Helm`) before the install proceeds.
- Ghost's built-in content filesystem stays on a PVC; for multi-replica or cloud-native setups, configure a third-party storage adapter (S3/GCS) out of chart scope.

## Contributing

Run locally:

```bash
make lint CHART=ghost
make template CHART=ghost
make validate CHART=ghost
```
