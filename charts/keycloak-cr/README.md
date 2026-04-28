# keycloak-cr

A Helm chart that renders the Keycloak Operator's custom resources (`Keycloak`, `KeycloakRealmImport`) plus a few convenience peripherals: HTTPRoute (Gateway API) or standalone Ingress, DB-credentials Secret, and a bootstrap-admin Secret.

This chart does **not** install the Keycloak Operator itself — install the [`keycloak-operator`](../keycloak-operator) chart (or the upstream raw YAML) first so the CRDs and operator Deployment are present before this chart is applied.

<br/>

## What it deploys

| Resource | API | Purpose |
|---|---|---|
| `Keycloak` | `k8s.keycloak.org/v2beta1` | Primary CR — the operator reconciles a StatefulSet + Service from this. Always rendered. |
| `KeycloakRealmImport` | `k8s.keycloak.org/v2beta1` | Optional. One-shot Job that imports an inline `RealmRepresentation`. |
| `HTTPRoute` | `gateway.networking.k8s.io/v1` | Optional. Routes traffic from a Gateway to the Keycloak Service the operator renders. |
| `HTTPRoute` (https-redirect) | `gateway.networking.k8s.io/v1` | Optional. 301-redirects HTTP → HTTPS on the same hostname. |
| `Ingress` | `networking.k8s.io/v1` | Optional. Standalone Ingress when Gateway API is unavailable or finer control is needed than `keycloak.ingress`. |
| `Secret` (DB credentials) | `v1` | Optional. Convenience helper — render the username/password Secret inline rather than via ExternalSecrets. |
| `Secret` (bootstrap admin) | `v1` | Optional. Convenience helper — render the first-boot admin user/password. |

<br/>

## Prerequisites

- Kubernetes **1.25+**
- The [Keycloak Operator](https://www.keycloak.org/operator/installation) installed (provides the `Keycloak` and `KeycloakRealmImport` CRDs and the controller Pod). Use the [`keycloak-operator`](../keycloak-operator) chart from this repo, or the upstream raw YAML.
- A reachable database (PostgreSQL recommended). The Keycloak Operator does **not** ship a database — bring your own. Most users pair this chart with the [`postgresql`](../postgresql) chart from this repo.
- For `httproute.enabled: true`, [Gateway API](https://gateway-api.sigs.k8s.io/) CRDs and a Gateway controller (e.g. NGINX Gateway Fabric).

<br/>

## Install

<br/>

### OCI registry (Helm 3.8+)

```bash
helm install keycloak oci://ghcr.io/somaz94/charts/keycloak-cr \
  --version 0.1.0 \
  --namespace keycloak \
  -f my-values.yaml
```

<br/>

### Classic Helm repo

```bash
helm repo add somaz94 https://charts.somaz.blog
helm repo update
helm install keycloak somaz94/keycloak-cr \
  --namespace keycloak \
  -f my-values.yaml
```

<br/>

## Quick examples

<br/>

### 1. Minimal — single instance with an external DB Secret

The DB Secret already exists (created by the `postgresql` chart, ExternalSecrets, etc.). The chart only renders the `Keycloak` CR.

```yaml
keycloak:
  instances: 1
  hostname:
    hostname: auth.example.com
    strict: true
  proxy:
    headers: xforwarded                  # behind a TLS-terminating gateway
  db:
    vendor: postgres
    host: keycloak-postgresql.keycloak.svc
    database: keycloak
    existingSecret: keycloak-db-credentials
    usernameSecretKey: username
    passwordSecretKey: password
```

<br/>

### 2. Realm import — inline RealmRepresentation

Use this for small, declarative realms that fit comfortably in `values.yaml`. For exports larger than ~50 KB, prefer Example 3.

```yaml
keycloak:
  hostname: { hostname: auth.example.com, strict: true }
  proxy: { headers: xforwarded }
  db:
    vendor: postgres
    host: keycloak-postgresql.keycloak.svc
    database: keycloak
    existingSecret: keycloak-db-credentials

realmImport:
  enabled: true
  realm:
    realm: concrit
    enabled: true
    sslRequired: external
    registrationAllowed: false
    groups:
      - name: server
      - name: global-admin
```

<br/>

### 3. Realm import — large export from a JSON file

The `KeycloakRealmImport` CRD only accepts the realm inline (`spec.realm`) — it does not natively read from a ConfigMap. For large `kc.sh export` outputs, use `--set-file` to inline the JSON at install time:

```bash
helm install keycloak oci://ghcr.io/somaz94/charts/keycloak-cr \
  -n keycloak -f values.yaml \
  --set realmImport.enabled=true \
  --set-file realmImport.realm=./realm-concrit.json
```

For declarative GitOps (ArgoCD / Flux), commit the JSON, convert to YAML once, and embed it under `realmImport.realm` — Helm renders large YAML/JSON values without issue.

<br/>

### 4. With HTTPRoute and chart-rendered DB Secret

End-to-end install: chart renders the DB Secret and an HTTPRoute attached to a shared Gateway. Suitable for dev / single-tenant clusters.

```yaml
keycloak:
  instances: 1
  hostname: { hostname: auth.example.com, strict: true }
  proxy: { headers: xforwarded }
  db:
    vendor: postgres
    host: keycloak-postgresql.keycloak.svc
    database: keycloak
    # existingSecret left empty → chart-rendered Secret below is used

dbSecret:
  enabled: true
  username: keycloak
  password: change-me-in-vault         # rotate post-install

adminSecret:
  enabled: true
  username: admin
  password: change-me-in-vault         # rotate post-install via the admin UI

httproute:
  enabled: true
  parentRefs:
    - name: app
      namespace: nginx-gateway
      sectionName: https
  hostnames:
    - auth.example.com
  rules:
    - matches:
        - path: { type: PathPrefix, value: / }
      backendRefs:
        - port: 8080                   # name defaults to "<release>-service"
  httpsRedirect:
    enabled: true                      # 301 from the HTTP listener on the same Gateway
```

<br/>

### 5. HA + escape hatch (`specExtra`)

For surfaces this chart does not surface explicitly (e.g. `cache`, `httpManagement`, `imagePullSecrets` on a non-default field), use the top-level escape hatch.

```yaml
keycloak:
  instances: 3
  resources:
    requests: { cpu: "1", memory: 2Gi }
    limits:   { cpu: "2", memory: 4Gi }
  hostname: { hostname: auth.example.com, strict: true }
  proxy: { headers: xforwarded }
  db: { vendor: postgres, host: keycloak-postgresql.keycloak.svc, database: keycloak, existingSecret: keycloak-db-credentials }

  # mergeOverwrite semantics — anything below overrides chart-managed keys when keys collide.
  specExtra:
    cache:
      configMapFile:
        name: keycloak-cache-config
        key: cache-ispn.xml
    httpManagement:
      port: 9000
```

<br/>

## Values reference

### Top-level

| Key | Type | Default | Description |
|---|---|---|---|
| `name` | string | `""` | Override the chart-derived resource name (defaults to release name). |
| `commonLabels` | object | `{}` | Labels added to every resource. |
| `commonAnnotations` | object | `{}` | Annotations added to every resource. |
| `resourceMetadata.<resource>.{labels,annotations}` | object | `{}` | Per-resource metadata override. Resources: `keycloak`, `realmImport`, `httproute`, `ingress`, `dbSecret`, `adminSecret`. |

### `keycloak`

| Key | Type | Default | Description |
|---|---|---|---|
| `instances` | int | `1` | Number of Keycloak server pods. Use 2+ for HA (configure cache for distributed mode). |
| `image` | string | `""` | Container image override. Empty → operator-default. |
| `startOptimized` | string\|bool | `""` | `"true"` / `"false"` / empty. Set only for pre-augmented custom images. |
| `imagePullSecrets` | list | `[]` | Pull secrets attached to the server Pods. |
| `hostname.hostname` | string | `""` | FQDN clients use to reach Keycloak. **Required for `proxy.headers != ""`** to avoid admin redirect loops. |
| `hostname.admin` | string | `""` | Optional separate admin hostname. |
| `hostname.strict` | bool | `true` | Disable header-based hostname resolution. |
| `hostname.backchannelDynamic` | bool | `false` | Hostname v2 — enable for split private-network access. |
| `http.httpEnabled` | bool | `true` | Enable plaintext HTTP listener (recommended behind TLS-terminating gateway). |
| `http.httpPort` | int | `8080` | HTTP listener port. |
| `http.httpsPort` | int | `8443` | HTTPS listener port. |
| `http.tlsSecret` | string | `""` | Secret for HTTPS termination at Keycloak (used when `proxy=passthrough`). |
| `http.annotations` / `.labels` | object | `{}` | Operator-rendered Service metadata. |
| `proxy.headers` | string | `""` | `""` / `xforwarded` / `forwarded`. Set when behind a TLS-terminating gateway. |
| `db.vendor` | string | `postgres` | DB vendor (`postgres`, `mariadb`, `mysql`, `mssql`, `oracle`, `h2`). |
| `db.host` / `.port` / `.database` / `.schema` / `.url` | string/int | see values.yaml | Connection params. `url` overrides host/port/database. |
| `db.existingSecret` | string | `""` | Pre-existing Secret holding DB username + password. Falls back to chart-rendered `dbSecret` when both empty. |
| `db.usernameSecretKey` / `.passwordSecretKey` | string | `username` / `password` | Keys inside the DB Secret. |
| `db.poolMinSize` / `.poolInitialSize` / `.poolMaxSize` | int | `0` | Connection pool sizing (0 = operator default). |
| `bootstrapAdmin.userSecret` | string | `""` | Pre-existing Secret with `username` + `password`. Falls back to chart-rendered `adminSecret` when both empty. |
| `bootstrapAdmin.serviceSecret` | string | `""` | Pre-existing Secret with `client-id` + `client-secret`. |
| `resources` | object | `{}` | Compute resources for the Keycloak server Pods. |
| `scheduling` | object | `{}` | Pod scheduling (`nodeSelector`, `tolerations`, `affinity`, `priorityClassName`, …). |
| `features.enabled` / `.disabled` | list | `[]` | Keycloak server feature flags. |
| `ingress.enabled` | bool | `false` | Operator-rendered Ingress. Off by default — chart prefers HTTPRoute. |
| `ingress.className` / `.annotations` / `.labels` | — | `""` / `{}` | Standard Ingress metadata. |
| `networkPolicy.enabled` | bool | `false` | Operator-rendered NetworkPolicy. |
| `tracing.enabled` | bool | `false` | OpenTelemetry tracing. |
| `tracing.endpoint` / `.protocol` / `.samplerType` / `.samplerRatio` | — | — | Tracing config. |
| `transaction.xaEnabled` | bool\|null | `null` | Force XA / non-XA transactions. `null` = operator default. |
| `truststores` | object | `{}` | Map of name → `{ secret, configMap }` passed through to `spec.truststores`. |
| `additionalOptions` | list | `[]` | `KC_*` flag pass-through. Each entry: `{ name, value }` or `{ name, secret: { name, key, optional } }`. |
| `env` | list | `[]` | Env vars on Keycloak Pods (use `additionalOptions` for first-class flags). |
| `specExtra` | object | `{}` | **Escape hatch.** Merged into `spec` (top-level) of the Keycloak CR. |

### `realmImport`

| Key | Type | Default | Description |
|---|---|---|---|
| `enabled` | bool | `false` | Render a `KeycloakRealmImport` CR. |
| `keycloakCRName` | string | `""` | Target Keycloak CR name. Defaults to this chart's main Keycloak CR. |
| `realm` | object | `{}` | Inline `RealmRepresentation`. The Keycloak CRD does not natively load from a ConfigMap — use `--set-file realmImport.realm=path/to/realm.json` for large exports. |
| `placeholders` | object | `{}` | Realm import placeholder substitutions (typed as `{ secret: { name, key, optional } }` per CRD). |
| `resources` | object | `{}` | Compute resources for the import Job (NOT for Keycloak itself). |
| `specExtra` | object | `{}` | Escape hatch merged into `spec` of the KeycloakRealmImport. |

### `dbSecret` / `adminSecret`

| Key | Type | Default | Description |
|---|---|---|---|
| `enabled` | bool | `false` | Render the convenience Secret. |
| `name` | string | `""` | Secret name. Defaults: `<release>-db-credentials` / `<release>-bootstrap-admin`. |
| `username` / `password` | string | `""` | **Plaintext** values rendered into the Secret. **Rotate post-install** or use ExternalSecrets / Vault. |
| `usernameKey` / `passwordKey` | string | `username` / `password` | Keys inside the Secret. |

### `ingress` (chart-rendered, standalone Ingress)

Use this block when Gateway API is unavailable in the cluster, or when the operator's built-in `keycloak.ingress` field is too restrictive (no annotation control, single path, no TLS list). Mutually exclusive with `httproute.enabled` and `keycloak.ingress.enabled` — pick one routing method.

| Key | Type | Default | Description |
|---|---|---|---|
| `enabled` | bool | `false` | Render a standalone `networking.k8s.io/v1` Ingress. |
| `className` | string | `""` | `ingressClassName` (e.g. `nginx`, `traefik`, `alb`). |
| `host` | string | `""` | FQDN clients use to reach Keycloak. |
| `path` / `pathType` | string | `/` / `Prefix` | Default rule path. |
| `annotations` | object | `{}` | Ingress annotations (e.g. cert-manager, ALB target type, NGINX rewrite). |
| `tls[]` | list | `[]` | TLS entries `{ hosts, secretName }`. |
| `backend.serviceName` / `.servicePort` | string / int | empty / `8080` | Backend Service override. Empty → operator-rendered `<release>-service`. |
| `extraPaths[]` | list | `[]` | Additional paths on the same host (`/admin`, `/metrics`, …). |

### `httproute`

| Key | Type | Default | Description |
|---|---|---|---|
| `enabled` | bool | `false` | Render an HTTPRoute. |
| `parentRefs[]` | list | `[]` | Gateway references (`{ name, namespace, sectionName, port }`). |
| `hostnames[]` | list | `[]` | Hostnames matched on the parent Gateway. |
| `rules[]` | list | one default | HTTPRoute rules. Backend defaults to `<release>-service:8080`. |
| `httpsRedirect.enabled` | bool | `false` | Render a sibling HTTPRoute that 301-redirects HTTP → HTTPS. |
| `httpsRedirect.statusCode` | int | `301` | Redirect status. |
| `httpsRedirect.parentRefs` / `.port` | list / int | empty / unset | Optional override (falls back to `parentRefs` and the Gateway's HTTPS port). |

<br/>

## Notes

<br/>

### Operator dependency

The Keycloak Operator must be running in the cluster before this chart is applied — otherwise the CR will be admitted but not reconciled. The simplest install order:

```bash
# 1. Operator + CRDs
helm install keycloak-operator oci://ghcr.io/somaz94/charts/keycloak-operator -n keycloak-system --create-namespace

# 2. Database (this repo's postgresql chart, or your own)
helm install keycloak-postgresql oci://ghcr.io/somaz94/charts/postgresql -n keycloak --create-namespace -f db-values.yaml

# 3. Keycloak CR + realm
helm install keycloak oci://ghcr.io/somaz94/charts/keycloak-cr -n keycloak -f keycloak-values.yaml
```

<br/>

### `proxy.headers` and `hostname.hostname`

When Keycloak sits behind a TLS-terminating gateway (Ingress, NGF, Istio, …), set both `keycloak.proxy.headers: xforwarded` **and** `keycloak.hostname.hostname: <fqdn>`. Skipping the hostname causes the admin console to redirect-loop on first login.

<br/>

### Plaintext secrets

`dbSecret` and `adminSecret` are convenience helpers. The values are rendered as plaintext into the Helm release manifest and the Secret. Do **not** commit production passwords into `values.yaml` — use ExternalSecrets, Vault, or rotate them from the admin UI / `kcadm.sh` immediately after install.

<br/>

## License

[Apache-2.0](../../LICENSE)
