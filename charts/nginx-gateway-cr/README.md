# nginx-gateway-cr

A Helm chart that deploys [NGINX Gateway Fabric](https://github.com/nginx/nginx-gateway-fabric) custom resources alongside the upstream NGF controller chart.

The upstream chart installs the controller and CRDs, but does **not** create the tenant-level resources you actually route traffic through. This chart fills that gap with a flexible, multi-Gateway-friendly schema.

## What it deploys

| Resource | API | Purpose |
|---|---|---|
| `Gateway` | `gateway.networking.k8s.io/v1` | One per entry in `gateways[]`, with shorthand or fully custom listeners |
| `NginxProxy` | `gateway.nginx.org/v1alpha2` | One per Gateway, configures the dataplane Service + nginx-level options |
| `ReferenceGrant` | `gateway.networking.k8s.io/v1beta1` | Optional. Cross-namespace access (e.g. Gateway → TLS Secret in another ns) |
| `ServiceMonitor` (controller) | `monitoring.coreos.com/v1` | Optional. Scrapes the NGF control-plane metrics |
| `ServiceMonitor` (dataplane) | `monitoring.coreos.com/v1` | Optional. Scrapes nginx pod metrics from each NginxProxy |

## Prerequisites

- Kubernetes **1.25+**
- [NGINX Gateway Fabric](https://github.com/nginx/nginx-gateway-fabric) controller installed (provides the `NginxProxy` CRD and `gateway.nginx.org` API group)
- [Gateway API](https://gateway-api.sigs.k8s.io/) CRDs installed (`gateway.networking.k8s.io`)
- For `serviceMonitor.*.enabled: true`, the [Prometheus Operator](https://github.com/prometheus-operator/prometheus-operator) (typically via [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack))

## Install

### OCI registry (Helm 3.8+)

```bash
helm install ngf-cr oci://ghcr.io/somaz94/charts/nginx-gateway-cr \
  --version 0.2.0 \
  --namespace nginx-gateway \
  -f my-values.yaml
```

### Classic Helm repo

```bash
helm repo add somaz94 https://charts.somaz.blog
helm repo update
helm install ngf-cr somaz94/nginx-gateway-cr \
  --namespace nginx-gateway \
  -f my-values.yaml
```

## Quick examples

### Single HTTPS gateway

```yaml
gateways:
  - name: app
    loadBalancerIP: 10.0.0.10
    https:
      enabled: true
      hostname: "*.example.com"
      tlsSecretName: wildcard-example-tls
```

### Multiple gateways with per-gateway overrides

```yaml
proxy:
  replicas: 1
  externalTrafficPolicy: Cluster

gateways:
  - name: app
    loadBalancerIP: 10.0.0.10
    https:
      enabled: true
      hostname: "*.example.com"
      tlsSecretName: wildcard-example-tls
    proxy:
      replicas: 3                          # override default

  - name: public
    loadBalancerIP: 10.0.0.11
    proxy:
      service:
        annotations:
          metallb.universe.tf/address-pool: prod-pool
```

### Custom listener (TLS passthrough)

```yaml
gateways:
  - name: tcp
    loadBalancerIP: 10.0.0.12
    listeners:                             # full override; shorthand ignored
      - name: tls-passthrough
        protocol: TLS
        port: 8443
        tls:
          mode: Passthrough
        allowedRoutes:
          kinds:
            - kind: TLSRoute
```

### Cross-namespace TLS secret via ReferenceGrant

```yaml
gateways:
  - name: app
    loadBalancerIP: 10.0.0.10
    https:
      enabled: true
      hostname: "*.example.com"
      tlsSecretName: wildcard-example-tls

referenceGrants:
  - name: gateway-to-tls
    namespace: tls                         # ReferenceGrant lives in TARGET namespace
    from:
      - group: gateway.networking.k8s.io
        kind: Gateway
        namespace: default
    to:
      - group: ""
        kind: Secret
        name: wildcard-example-tls
```

### Prometheus scraping

```yaml
serviceMonitor:
  namespace: monitoring
  releaseLabel: kube-prometheus-stack
  controller:
    enabled: true
  dataplane:
    enabled: true
```

## Values reference

### Top-level

| Key | Type | Default | Description |
|---|---|---|---|
| `commonLabels` | object | `{}` | Labels added to every resource. |
| `commonAnnotations` | object | `{}` | Annotations added to every resource. |
| `gatewayClassName` | string | `ngf` | Default GatewayClassName. Per-gateway overridable. |

### `listenerDefaults`

Used when a Gateway entry does not set `listeners` directly.

| Key | Type | Default | Description |
|---|---|---|---|
| `http.enabled` | bool | `true` | Add an HTTP listener. |
| `http.port` | int | `80` | HTTP listener port. |
| `http.allowedRoutes` | object | `{namespaces: {from: All}}` | `allowedRoutes` for the HTTP listener. |
| `https.enabled` | bool | `false` | Add an HTTPS listener. |
| `https.port` | int | `443` | HTTPS listener port. |
| `https.hostname` | string | `""` | Listener hostname (wildcards supported). |
| `https.tlsSecretName` | string | `""` | TLS Secret used for termination. |
| `https.allowedRoutes` | object | `{namespaces: {from: All}}` | `allowedRoutes` for the HTTPS listener. |

### `proxy` (defaults applied to every NginxProxy)

| Key | Type | Default | Description |
|---|---|---|---|
| `replicas` | int | `1` | Dataplane Deployment replicas. |
| `resources` | object | `{}` | Container resources (requests/limits). |
| `nodeSelector` | object | `{}` | Pod nodeSelector. |
| `tolerations` | list | `[]` | Pod tolerations. |
| `affinity` | object | `{}` | Pod affinity. |
| `podAnnotations` | object | `{}` | Pod template annotations. |
| `podLabels` | object | `{}` | Pod template labels. |
| `service.type` | string | `LoadBalancer` | Service type. |
| `service.externalTrafficPolicy` | string | `Cluster` | `externalTrafficPolicy` (`Cluster` or `Local`). |
| `service.loadBalancerClass` | string | `""` | LoadBalancer class (e.g. `service.k8s.aws/nlb`). |
| `service.loadBalancerSourceRanges` | list | `[]` | Restrict source IPs at the LB. |
| `service.annotations` | object | `{}` | Service annotations. |
| `service.labels` | object | `{}` | Service labels. |
| `logging.errorLevel` | string | `""` | nginx error_log level. |
| `metrics` | object | `{}` | Passthrough into `spec.metrics`. |
| `rewriteClientIP` | object | `{}` | Passthrough into `spec.rewriteClientIP` (only emitted if `mode` set). |
| `telemetry` | object | `{}` | Passthrough into `spec.telemetry`. |
| `disableHTTP2` | bool | `false` | Disable HTTP/2 on the dataplane. |
| `ipFamily` | string | `""` | `ipv4`, `ipv6`, or `dual`. |
| `kubernetesExtra` | object | `{}` | **Escape hatch.** Merged into `spec.kubernetes`. |
| `specExtra` | object | `{}` | **Escape hatch.** Merged into `spec` (top-level). |

### `gateways[]`

| Key | Type | Required | Description |
|---|---|---|---|
| `name` | string | yes | Gateway name. NginxProxy is named `<name>-proxy`. |
| `loadBalancerIP` | string | no | Static LB IP for the dataplane Service. |
| `gatewayClassName` | string | no | Override top-level `gatewayClassName`. |
| `labels` | object | no | Extra labels on Gateway + NginxProxy. |
| `annotations` | object | no | Extra annotations on Gateway + NginxProxy. |
| `http` | object | no | Listener shorthand (overrides `listenerDefaults.http`). |
| `https` | object | no | Listener shorthand (overrides `listenerDefaults.https`). |
| `listeners` | list | no | Full listener list. **If set, shorthand is ignored.** |
| `proxy` | object | no | Per-gateway NginxProxy overrides (deep-merged with top-level `proxy`). |

### `referenceGrants[]`

| Key | Type | Required | Description |
|---|---|---|---|
| `name` | string | yes | ReferenceGrant name. |
| `namespace` | string | yes | Target namespace (the one being granted access TO). |
| `from` | list | yes | Passthrough into `spec.from`. |
| `to` | list | yes | Passthrough into `spec.to`. |

### `serviceMonitor`

| Key | Type | Default | Description |
|---|---|---|---|
| `namespace` | string | `monitoring` | Namespace where ServiceMonitors are created. |
| `releaseLabel` | string | `kube-prometheus-stack` | `release` label for kube-prometheus-stack discovery. |
| `interval` | string | `30s` | Scrape interval (shared by both monitors). |
| `scrapeTimeout` | string | `""` | Optional scrape timeout. |
| `additionalLabels` | object | `{}` | Extra labels on the ServiceMonitor metadata. |
| `controller.enabled` | bool | `false` | Create the controller ServiceMonitor. |
| `controller.path` | string | `/metrics` | Scrape path. |
| `controller.port` | string | `metrics` | Service port name. |
| `controller.selector` | object | matches NGF | Service selector. |
| `controller.namespaceSelector` | object | `{}` | Empty = `Release.Namespace` only. |
| `controller.additionalEndpoints` | list | `[]` | Extra endpoint entries appended to `spec.endpoints`. |
| `dataplane.*` | — | — | Same shape as `controller.*`. |

## Notes on `externalTrafficPolicy`

- Use `Cluster` (default) when in-cluster pods may resolve the LoadBalancer IP and need traffic to reach the dataplane regardless of which node receives it.
- Use `Local` when you must preserve the client source IP and accept that only nodes running a dataplane pod will accept traffic.

## Escape hatches

If a field exists on `NginxProxy` but is not surfaced explicitly:

```yaml
proxy:
  specExtra:
    kubernetes:
      daemonSet: {}                        # use a DaemonSet instead of Deployment

  kubernetesExtra:
    deployment:
      strategy:
        type: RollingUpdate
        rollingUpdate:
          maxUnavailable: 0
```

`mergeOverwrite` semantics — escape hatch keys override chart-managed keys when they collide. Prefer first-class fields when available.

## License

[Apache-2.0](../../LICENSE)
