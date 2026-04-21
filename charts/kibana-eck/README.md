# kibana-eck

A Helm chart for Kibana on Kubernetes via the [ECK operator](https://github.com/elastic/cloud-on-k8s).

The chart renders the ECK `Kibana` Custom Resource plus optional siblings (ServiceAccount, PDB, HTTPRoute, Ingress, BackendTLSPolicy, ServiceMonitor, NetworkPolicy, ReferenceGrant). Defaults target a single-replica setup; HA is opt-in.

<br/>

## What it deploys

| Resource | API | Purpose |
|---|---|---|
| `Kibana` | `kibana.k8s.elastic.co/v1` | The Kibana CR. ECK reconciles the Deployment + Service. |
| `ServiceAccount` | `v1` | Optional. Dedicated SA for IRSA / Workload Identity. |
| `PodDisruptionBudget` | `policy/v1` | Optional. Required for zero-downtime rolling updates. |
| `HTTPRoute` | `gateway.networking.k8s.io/v1` | Optional. Gateway API route for external access. |
| `Ingress` | `networking.k8s.io/v1` | Optional. Legacy path for non-Gateway-API clusters. |
| `BackendTLSPolicy` + CA `ConfigMap` | `gateway.networking.k8s.io/v1`, `v1` | Optional. TLS verification from Gateway (when Kibana serves HTTPS). |
| `ServiceMonitor` | `monitoring.coreos.com/v1` | Optional. Prometheus scrape config. |
| `NetworkPolicy` | `networking.k8s.io/v1` | Optional. Lock down ingress/egress. |
| `ReferenceGrant` | `gateway.networking.k8s.io/v1beta1` | Optional. Cross-namespace references from HTTPRoutes / other Kibanas. |

<br/>

## Versioning

- `Chart.yaml` **version** — chart's own SemVer, bumped manually via `make bump CHART=kibana-eck LEVEL=patch|minor|major`.
- `Chart.yaml` **appVersion** — the Kibana Stack version shipped (defaults `values.version`). Bumped by `./upgrade.sh`.
- `values.yaml` **version** — rendered into `spec.version` of the Kibana CR. Override to pin at install time.
- `values.yaml` **image** — optional full image reference override.

`upgrade.sh` enforces **Kibana version ≤ Elasticsearch version** by reading the sibling `../elasticsearch-eck/values.yaml`.

<br/>

## Prerequisites

- Kubernetes **1.25+**
- [ECK Operator](https://github.com/elastic/cloud-on-k8s) installed:
  ```bash
  helm repo add elastic https://helm.elastic.co
  helm install eck-operator elastic/eck-operator -n elastic-system --create-namespace
  ```
- An Elasticsearch CR (typically deployed via the [elasticsearch-eck](../elasticsearch-eck/) sibling chart) in the referenced namespace
- For `httproute.enabled: true`: Gateway API CRDs + a Gateway controller
- For `serviceMonitor.enabled: true`: [Prometheus Operator](https://github.com/prometheus-operator/prometheus-operator)

<br/>

## Install

### OCI registry (Helm 3.8+)

```bash
helm install kibana oci://ghcr.io/somaz94/charts/kibana-eck \
  --version 0.1.1 \
  --namespace logging \
  --set elasticsearchRef.name=elasticsearch \
  -f my-values.yaml
```

<br/>

### Classic Helm repo

```bash
helm repo add somaz94 https://charts.somaz.blog
helm repo update
helm install kibana somaz94/kibana-eck \
  --namespace logging \
  --set elasticsearchRef.name=elasticsearch
```

<br/>

## Quick examples

### 1. Minimal (single replica, linked to sibling ES)

```yaml
elasticsearchRef:
  name: elasticsearch      # the Elasticsearch CR name in the same namespace
```

<br/>

### 2. HA (2+ replicas + PDB)

```yaml
replicas: 2

podTemplate:
  topologySpreadConstraints:
    - maxSkew: 1
      topologyKey: kubernetes.io/hostname
      whenUnsatisfiable: DoNotSchedule
      labelSelector:
        matchLabels:
          common.k8s.elastic.co/type: kibana

podDisruptionBudget:
  enabled: true
  maxUnavailable: 1
```

<br/>

### 3. Behind a Gateway (NGF) with TLS upstream

```yaml
# Serve plain HTTP on :5601; TLS terminated at the Gateway.
http:
  tls:
    selfSignedCertificate:
      disabled: true

httproute:
  enabled: true
  parentRefs:
    - name: ngf
      namespace: nginx-gateway
  hostnames:
    - kibana.example.com
  rules:
    - matches:
        - path: {type: PathPrefix, value: /}
      backendRefs:
        - port: 5601

config:
  server.publicBaseUrl: https://kibana.example.com
```

<br/>

### 4. Legacy Ingress (ingress-nginx)

```yaml
ingress:
  enabled: true
  className: nginx
  host: kibana.example.com
  annotations:
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
```

<br/>

### 5. Advanced — escape hatches

```yaml
# Extra kibana.yml settings
config:
  logging.root.level: info
  xpack.fleet.enabled: true

# Mount a custom keystore from a Secret
secureSettings:
  - secretName: kibana-saml-settings

# Stack monitoring: ship Kibana metrics/logs to another ES cluster
monitoring:
  metrics:
    elasticsearchRefs:
      - name: monitoring-es
        namespace: observability

# Arbitrary fields merged into spec
specExtra:
  revisionHistoryLimit: 5

# Arbitrary fields merged into spec.podTemplate
podTemplateExtra:
  spec:
    dnsPolicy: ClusterFirst
```

<br/>

## Values reference

See [values.yaml](values.yaml) and [values.schema.json](values.schema.json) for the complete shape. Highlights:

<br/>

### Top-level

| Key | Default | Description |
|---|---|---|
| `name` | `""` | CR name. Empty → Helm release name. |
| `version` | `"9.3.3"` | Kibana version. Must be ≤ linked ES version. |
| `image` | `""` | Optional image override. |
| `replicas` | `1` | Number of Kibana pods. |
| `elasticsearchRef.name` | `elasticsearch` | ES CR name (same namespace unless `namespace` is set — requires ReferenceGrant). |
| `nodeOptions` | `["--max-old-space-size=1800"]` | NODE_OPTIONS env var on the container. |
| `resources` | `100m/2Gi → 1000m/2Gi` | Container resources. |
| `http.tls.selfSignedCertificate.disabled` | `true` | Kibana serves plain HTTP on :5601 by default (ingress terminates TLS). Set back to `{}` to enable ECK self-signed HTTPS. |
| `config` | `{}` | Free-form kibana.yml content. Secure-cookie settings auto-added when TLS is disabled. |
| `specExtra` / `podTemplateExtra` / `containerExtra` | `{}` | Escape hatches. |

<br/>

### `podTemplate` / `container`

Structured passthrough for pod-level (`nodeSelector`, `affinity`, `tolerations`, `topologySpreadConstraints`, `priorityClassName`, `initContainers`, `sidecars`, `volumes`, `podSecurityContext`) and container-level (`env`, `envFrom`, `volumeMounts`, `livenessProbe`, `readinessProbe`, `startupProbe`, `lifecycle`, `securityContext`) fields.

<br/>

### Optional resources

| Block | Flag | Notes |
|---|---|---|
| ServiceAccount | `serviceAccount.create` | Creates SA; auto-wires via `serviceAccountName`. |
| PodDisruptionBudget | `podDisruptionBudget.enabled` | External `policy/v1` PDB (Kibana is a Deployment). |
| HTTPRoute | `httproute.enabled` | Gateway API route; defaults backend to `<fullname>-kb-http:5601`. |
| Ingress | `ingress.enabled` | Legacy, kept for migration. |
| BackendTLSPolicy | `backendTLSPolicy.enabled` | Only when Kibana serves HTTPS + Gateway validates backend TLS. |
| ServiceMonitor | `serviceMonitor.enabled` | Prometheus scrape config. |
| NetworkPolicy | `networkPolicy.enabled` | Full NetworkPolicy shape exposed (ingress/egress arrays). |
| ReferenceGrant | `referenceGrants[]` | List of cross-namespace grants. |

<br/>

## Maintaining this chart

```bash
cd charts/kibana-eck
./upgrade.sh --dry-run          # preview
./upgrade.sh                    # bump to latest GA (enforces version ≤ ES)
./upgrade.sh --version 9.1.2    # pin
./upgrade.sh --rollback         # restore files

# After review:
make bump CHART=kibana-eck LEVEL=minor
make lint CHART=kibana-eck
make template CHART=kibana-eck
```

<br/>

## License

Apache-2.0. See [LICENSE](../../LICENSE).
