# prometheus-cr

Data-driven **Prometheus Operator monitoring** custom resources, deployed as a Helm release alongside kube-prometheus-stack / prometheus-operator.

The [prometheus-operator](https://github.com/prometheus-operator/prometheus-operator) (via kube-prometheus-stack) installs the operator and CRDs but **leaves app-level monitoring CRs** (`ServiceMonitor`, `PodMonitor`, `PrometheusRule`, ...) to each consumer — usually hand-written per component and duplicated across repos. This chart closes that gap so cross-cutting monitoring config (scraping a third-party target, a blackbox probe, a shared alert-rule set) is managed declaratively in Git as one Helm release.

<br/>

## What it deploys

| Resource | API | Created from |
|---|---|---|
| `ServiceMonitor` | `monitoring.coreos.com/v1` | `serviceMonitors[]` |
| `PodMonitor` | `monitoring.coreos.com/v1` | `podMonitors[]` |
| `PrometheusRule` | `monitoring.coreos.com/v1` | `prometheusRules[]` |
| `Probe` | `monitoring.coreos.com/v1` | `probes[]` |
| `ScrapeConfig` | `monitoring.coreos.com/v1alpha1` | `scrapeConfigs[]` |

Every list defaults to empty, so an unconfigured `helm install` creates nothing.

<br/>

## Prerequisites

- Kubernetes >= 1.25
- Prometheus Operator and its CRDs already installed — typically via kube-prometheus-stack or the prometheus-operator chart. This chart only creates monitoring CRs; it does not install the operator or its CRDs.
- A Prometheus that **selects** these resources. Creating a `ServiceMonitor` is not enough on its own — the Prometheus CR's `serviceMonitorSelector` / `ruleSelector` / `probeSelector` / `scrapeConfigSelector` (and matching `*NamespaceSelector`) must match. Either add the label the selector expects to `commonLabels`, or set the relevant `*SelectorNilUsesHelmValues: false` in kube-prometheus-stack.

<br/>

## Install

OCI registry:

```bash
helm install monitoring-config oci://ghcr.io/somaz94/charts/prometheus-cr \
  --namespace monitoring \
  -f my-values.yaml
```

Classic Helm repo:

```bash
helm repo add somaz94 https://charts.somaz.blog
helm install monitoring-config somaz94/prometheus-cr \
  --namespace monitoring \
  -f my-values.yaml
```

<br/>

## Quick examples

<br/>

### Scrape an app's Service

```yaml
commonLabels:
  release: kube-prometheus-stack   # so the stack's selector picks it up

serviceMonitors:
  - name: my-app
    selector:
      matchLabels:
        app.kubernetes.io/name: my-app
    namespaceSelector:
      matchNames:
        - my-app
    endpoints:
      - port: http-metrics
        path: /metrics
        interval: 30s
```

<br/>

### A shared alert-rule set

```yaml
prometheusRules:
  - name: platform-rules
    groups:
      - name: platform.rules
        rules:
          - alert: TargetDown
            expr: up == 0
            for: 5m
            labels:
              severity: critical
            annotations:
              summary: "{{ $labels.job }} target is down"
```

<br/>

### Blackbox probe of external endpoints

```yaml
probes:
  - name: external-endpoints
    jobName: blackbox
    prober:
      url: blackbox-exporter.monitoring.svc:9115
    module: http_2xx
    targets:
      staticConfig:
        static:
          - https://example.com
          - https://api.example.com
```

<br/>

### Scrape static targets outside the cluster

```yaml
scrapeConfigs:
  - name: external-nodes
    staticConfigs:
      - targets:
          - 192.0.2.10:9100
          - 192.0.2.11:9100
        labels:
          env: prod
    scrapeInterval: 30s
```

<br/>

## Values reference

<br/>

### Shared metadata

| Key | Type | Default | Description |
|---|---|---|---|
| `commonLabels` | map | `{}` | Labels added to every resource. Add the label your Prometheus selector expects here. |
| `commonAnnotations` | map | `{}` | Annotations added to every resource. |

<br/>

### `serviceMonitors[]`

| Key | Type | Required | Description |
|---|---|---|---|
| `name` | string | yes | ServiceMonitor name. |
| `namespace` | string | no | Target namespace (default: release namespace). |
| `selector` | map | no | Service label selector (defaults to match-all). |
| `namespaceSelector` | map | no | `{ any: true }` or `{ matchNames: [...] }`. |
| `endpoints` | list | no | Endpoint scrape configs (`port`, `path`, `interval`, `scheme`, `tlsConfig`, `relabelings`, ...). |
| `jobLabel` | string | no | Service label to use as the `job` label. |
| `targetLabels` / `podTargetLabels` | list | no | Labels to copy onto scraped metrics. |
| `sampleLimit` | integer | no | Per-scrape sample limit. |
| `labels` / `annotations` / `specExtra` | map | no | Extra metadata / escape hatch. |

<br/>

### `podMonitors[]`

| Key | Type | Required | Description |
|---|---|---|---|
| `name` | string | yes | PodMonitor name. |
| `namespace` | string | no | Target namespace (default: release namespace). |
| `selector` | map | no | Pod label selector (defaults to match-all). |
| `namespaceSelector` | map | no | `{ any: true }` or `{ matchNames: [...] }`. |
| `podMetricsEndpoints` | list | no | Pod endpoint scrape configs. |
| `jobLabel` | string | no | Pod label to use as the `job` label. |
| `podTargetLabels` | list | no | Pod labels to copy onto scraped metrics. |
| `sampleLimit` | integer | no | Per-scrape sample limit. |
| `labels` / `annotations` / `specExtra` | map | no | Extra metadata / escape hatch. |

<br/>

### `prometheusRules[]`

| Key | Type | Required | Description |
|---|---|---|---|
| `name` | string | yes | PrometheusRule name. |
| `namespace` | string | no | Target namespace (default: release namespace). |
| `groups` | list | yes | Rule groups: `{ name, interval?, rules[] }`; each rule is `{ alert\|record, expr, for?, labels?, annotations? }`. |
| `labels` / `annotations` / `specExtra` | map | no | Extra metadata / escape hatch. |

<br/>

### `probes[]`

| Key | Type | Required | Description |
|---|---|---|---|
| `name` | string | yes | Probe name. |
| `namespace` | string | no | Target namespace (default: release namespace). |
| `jobName` | string | no | Value of the `job` label. |
| `prober` | map | no | `{ url, scheme, path, proxyUrl }` of the prober (blackbox-exporter). |
| `module` | string | no | Prober module (e.g. `http_2xx`). |
| `targets` | map | no | `{ staticConfig: {...} }` or `{ ingress: {...} }`. |
| `interval` / `scrapeTimeout` | string | no | Scrape timing. |
| `labels` / `annotations` / `specExtra` | map | no | Extra metadata / escape hatch. |

<br/>

### `scrapeConfigs[]`

| Key | Type | Required | Description |
|---|---|---|---|
| `name` | string | yes | ScrapeConfig name. |
| `namespace` | string | no | Target namespace (default: release namespace). |
| `jobName` | string | no | Value of the `job` label. |
| `staticConfigs` | list | no | `{ targets: [...], labels: {...} }`. |
| `scrapeInterval` / `scrapeTimeout` | string | no | Scrape timing. |
| `metricsPath` | string | no | Metrics path (default `/metrics`). |
| `scheme` | string | no | `HTTP` \| `HTTPS`. |
| `relabelings` / `metricRelabelings` | list | no | Relabel configs. |
| `labels` / `annotations` | map | no | Extra metadata. |
| `specExtra` | map | no | Escape hatch — use for the many `*SDConfig` discovery variants not surfaced. |

<br/>

## License

[Apache-2.0](../../LICENSE)
