# nginx-gateway-cr

A Helm chart that deploys [NGINX Gateway Fabric](https://github.com/nginx/nginx-gateway-fabric) custom resources alongside the upstream NGF controller chart.

The upstream chart installs the controller and CRDs, but does **not** create the tenant-level resources you actually route traffic through. This chart fills that gap with a flexible, multi-Gateway-friendly schema.

<br/>

## What it deploys

| Resource | API | Purpose |
|---|---|---|
| `Gateway` | `gateway.networking.k8s.io/v1` | One per entry in `gateways[]`, with shorthand or fully custom listeners |
| `NginxProxy` | `gateway.nginx.org/v1alpha2` | One per Gateway, configures the dataplane Service + nginx-level options |
| `ReferenceGrant` | `gateway.networking.k8s.io/v1beta1` | Optional. Cross-namespace access (e.g. Gateway → TLS Secret in another ns) |
| `ClientSettingsPolicy` | `gateway.nginx.org/v1alpha1` | Optional. Client-side (downstream) nginx tuning — request body limits and keep-alive behaviour — attached to a Gateway or route |
| `ServiceMonitor` (controller) | `monitoring.coreos.com/v1` | Optional. Scrapes the NGF control-plane metrics via the Service |
| `ServiceMonitor` (dataplane) | `monitoring.coreos.com/v1` | Optional. Scrapes nginx pod metrics from the dataplane Service |
| `PodMonitor` (controller) | `monitoring.coreos.com/v1` | Optional. Scrapes the NGF control-plane Pod directly. **Recommended for NGF 2.x** (controller `/metrics` is exposed on the Pod, not the Service) |
| `PodMonitor` (dataplane) | `monitoring.coreos.com/v1` | Optional. Scrapes the dataplane (nginx) Pods directly |

<br/>

## Prerequisites

- Kubernetes **1.25+**
- [NGINX Gateway Fabric](https://github.com/nginx/nginx-gateway-fabric) controller installed (provides the `NginxProxy` CRD and `gateway.nginx.org` API group)
- [Gateway API](https://gateway-api.sigs.k8s.io/) CRDs installed (`gateway.networking.k8s.io`)
- For `serviceMonitor.*.enabled: true`, the [Prometheus Operator](https://github.com/prometheus-operator/prometheus-operator) (typically via [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack))

<br/>

## Install

These snippets install the latest published chart. To pin an exact chart version, add `--version <x.y.z>` — released versions are the GitHub Release tags named `nginx-gateway-cr-<version>`.

<br/>

### OCI registry (Helm 3.8+)

```bash
helm install ngf-cr oci://ghcr.io/somaz94/charts/nginx-gateway-cr \
  --namespace nginx-gateway \
  -f my-values.yaml
```

<br/>

### Classic Helm repo

```bash
helm repo add somaz94 https://charts.somaz.blog
helm repo update
helm install ngf-cr somaz94/nginx-gateway-cr \
  --namespace nginx-gateway \
  -f my-values.yaml
```

<br/>

## Quick examples

<br/>

### Single HTTPS gateway

```yaml
gateways:
  - name: app
    loadBalancerIP: 192.0.2.10
    https:
      enabled: true
      hostname: "*.example.com"
      tlsSecretName: wildcard-example-tls
```

<br/>

### Multiple gateways with per-gateway overrides

```yaml
proxy:
  replicas: 1
  externalTrafficPolicy: Cluster

gateways:
  - name: app
    loadBalancerIP: 192.0.2.10
    https:
      enabled: true
      hostname: "*.example.com"
      tlsSecretName: wildcard-example-tls
    proxy:
      replicas: 3                          # override default

  - name: public
    loadBalancerIP: 192.0.2.11
    proxy:
      service:
        annotations:
          metallb.universe.tf/address-pool: prod-pool
```

<br/>

### Custom listener (TLS passthrough)

```yaml
gateways:
  - name: tcp
    loadBalancerIP: 192.0.2.12
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

<br/>

### Cross-namespace TLS secret via ReferenceGrant

```yaml
gateways:
  - name: app
    loadBalancerIP: 192.0.2.10
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

<br/>

### Surviving an nginx reload without dropped keep-alive connections

An nginx reload (any config change — including a backend rollout that shifts
endpoints) shuts the old workers down gracefully, and graceful shutdown closes
idle keep-alive connections with no notice. HTTP/1.1 has no GOAWAY equivalent, so
a client that reuses such a connection at that exact moment sees a connection
reset instead of a response.

Holding idle connections open for at least as long as the client's own idle
timeout removes the race: the client either reuses the connection well inside the
window, or drops it first.

```yaml
clientSettingsPolicies:
  - name: public-keepalive
    targetRef:
      name: public                 # kind defaults to Gateway
    keepAlive:
      minTimeout: 21s              # >= the client's keep-alive idle timeout
```

Keep `minTimeout` at or below `keepAlive.timeout.server` (nginx's
`keepalive_timeout`, default `75s` when unset). The trade-off is that shutting-down
workers linger for up to `minTimeout` after each reload.

<br/>

### Prometheus scraping

For NGF 2.x, prefer `PodMonitor` for the controller because the upstream chart exposes `/metrics:9113` only on the Pod, not on the controller Service:

```yaml
podMonitor:
  namespace: monitoring
  releaseLabel: kube-prometheus-stack
  controller:
    enabled: true
  dataplane:
    enabled: true
```

`ServiceMonitor` works only when a Service in the namespace exposes the metrics port (e.g. via custom port config). When in doubt, use `PodMonitor`.

<br/>

## Values reference

The tables below mirror [`values.yaml`](values.yaml), which is authoritative; [`values.schema.json`](values.schema.json) enforces the shape.

<br/>

### Top-level

| Key | Type | Default | Description |
|---|---|---|---|
| `commonLabels` | object | `{}` | Labels added to every resource. |
| `commonAnnotations` | object | `{}` | Annotations added to every resource. |
| `gatewayClassName` | string | `ngf` | Default GatewayClassName. Per-gateway overridable. |

<br/>

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

<br/>

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

<br/>

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

<br/>

### `referenceGrants[]`

| Key | Type | Required | Description |
|---|---|---|---|
| `name` | string | yes | ReferenceGrant name. |
| `namespace` | string | yes | Target namespace (the one being granted access TO). |
| `from` | list | yes | Passthrough into `spec.from`. |
| `to` | list | yes | Passthrough into `spec.to`. |

<br/>

### `clientSettingsPolicies[]`

| Key | Type | Required | Description |
|---|---|---|---|
| `name` | string | yes | Policy name. |
| `namespace` | string | no | Defaults to the release namespace. A policy must share a namespace with its target. |
| `labels` | object | no | Extra labels on the policy. |
| `annotations` | object | no | Extra annotations on the policy. |
| `targetRef.name` | string | yes | Name of the object to attach to. |
| `targetRef.kind` | string | no | `Gateway` (default), `HTTPRoute`, or `GRPCRoute`. |
| `targetRef.group` | string | no | Defaults to `gateway.networking.k8s.io`. |
| `body.maxSize` | string | no | `client_max_body_size`. `"0"` disables the check. |
| `body.bufferSize` | string | no | `client_body_buffer_size`. A body larger than this is spilled to a temporary file. **Requires NGF >= 2.7.0**. |
| `body.timeout` | string | no | `client_body_timeout`. |
| `keepAlive.requests` | int | no | `keepalive_requests`. |
| `keepAlive.time` | string | no | `keepalive_time`. |
| `keepAlive.minTimeout` | string | no | `keepalive_min_timeout`. **Requires NGF >= 2.6.0** (nginx >= 1.27.4). |
| `keepAlive.timeout.server` | string | no | `keepalive_timeout` server value. |
| `keepAlive.timeout.header` | string | no | `Keep-Alive: timeout=N` response header. Only valid alongside `timeout.server`. |

Durations and sizes are strings in the CRD (`21s`, `500m`), so quote anything YAML
would otherwise read as a number. The values schema rejects unknown keys inside
these blocks on purpose: a mistyped field would otherwise be dropped silently and
produce an accepted policy that configures nothing.

Attaching to a `Gateway` applies the settings to every route on it; attach to an
`HTTPRoute` / `GRPCRoute` to scope them to one route.

<br/>

### `serviceMonitor` / `podMonitor`

Both blocks share the same shape (a `controller` and a `dataplane` sub-block plus shared metadata).

| Key | Type | Default | Description |
|---|---|---|---|
| `namespace` | string | `monitoring` | Namespace where the monitor objects are created. |
| `releaseLabel` | string | `kube-prometheus-stack` | `release` label for kube-prometheus-stack discovery. |
| `interval` | string | `30s` | Scrape interval (shared by both `controller` and `dataplane`). |
| `scrapeTimeout` | string | `""` | Optional scrape timeout. |
| `additionalLabels` | object | `{}` | Extra labels on the monitor metadata. |
| `controller.enabled` | bool | `false` | Create the controller monitor. |
| `controller.path` | string | `/metrics` | Scrape path. |
| `controller.port` | string | `metrics` | Service port name (ServiceMonitor) or container port name (PodMonitor). |
| `controller.selector` | object | matches NGF | Selector applied to the Service (ServiceMonitor) or Pod (PodMonitor). |
| `controller.namespaceSelector` | object | `{}` | Empty = `Release.Namespace` only. |
| `controller.additionalEndpoints` | list | `[]` | Extra endpoint entries appended to `spec.endpoints` / `spec.podMetricsEndpoints`. |
| `dataplane.*` | — | — | Same shape as `controller.*`. |

Use `podMonitor` for NGF 2.x controller (Pod port `metrics:9113` is not on the Service). Use `serviceMonitor` when a Service exposes the metrics port.

<br/>

## Notes on `externalTrafficPolicy`

- Use `Cluster` (default) when in-cluster pods may resolve the LoadBalancer IP and need traffic to reach the dataplane regardless of which node receives it.
- Use `Local` when you must preserve the client source IP and accept that only nodes running a dataplane pod will accept traffic.

<br/>

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

<br/>

## License

[Apache-2.0](../../LICENSE)
