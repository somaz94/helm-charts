# helm-charts

A collection of Helm charts maintained by [@somaz94](https://github.com/somaz94).

Charts are published to:

- **Helm repo** (classic): `https://charts.somaz.blog`
- **GHCR** (OCI registry): `oci://ghcr.io/somaz94/charts/<chart-name>`

<br/>

## Charts

| Chart | Version | Description |
|---|---|---|
| [nginx-gateway-cr](charts/nginx-gateway-cr) | `0.3.0` | Custom resources for NGINX Gateway Fabric — Gateway, NginxProxy, ReferenceGrant, plus ServiceMonitor / PodMonitor for Prometheus |
| [certmanager-letsencrypt](charts/certmanager-letsencrypt) | `0.2.0` | Let's Encrypt resources for cert-manager — multi-issuer / multi-certificate / multi-secret / optional Ingress, DNS-01 (Cloudflare, Route53, Cloud DNS, ...) |
| [elasticsearch-eck](charts/elasticsearch-eck) | `0.1.1` | Elasticsearch CR for ECK (Elastic Cloud on Kubernetes) — nodeSets[] array, HTTPRoute, Ingress, BackendTLSPolicy, PDB (native/external), ServiceMonitor, NetworkPolicy, ReferenceGrant, sysctl init container. Single-node default, HA opt-in. |
| [kibana-eck](charts/kibana-eck) | `0.1.1` | Kibana CR for ECK — auto-wired to an Elasticsearch CR via elasticsearchRef, HTTPRoute, Ingress, BackendTLSPolicy, PDB, ServiceMonitor, NetworkPolicy, ReferenceGrant. Sibling-version check in upgrade.sh. |
| [ghost](charts/ghost) | `0.1.2` | Ghost CMS (Node.js blog) — Deployment + PVC + optional bundled MySQL 8 (ConfigMap/Secret/PVC/Deployment/Service), backup CronJob, HTTPRoute + NGF ClientSettingsPolicy, Ingress, ServiceMonitor. `mysql.fullnameOverride` / `mysql.configMap.nameOverride` for adopting legacy resources. Suits self-hosted single-replica blogs. |
| [unity-mcp-server](charts/unity-mcp-server) | `0.1.0` | Unity MCP (Model Context Protocol) Server running FastMCP's StreamableHTTP transport — Deployment + Service + optional API-key Secret, HTTPRoute + NGF ProxySettingsPolicy (SSE-friendly), Ingress. Bring-your-own-image (build from CoplayDev/unity-mcp). |

<br/>

## Install

<br/>

### Classic Helm repo

```bash
helm repo add somaz94 https://charts.somaz.blog
helm repo update
helm search repo somaz94
helm install <release> somaz94/<chart-name>
```

<br/>

### OCI registry (Helm 3.8+)

```bash
helm install <release> oci://ghcr.io/somaz94/charts/<chart-name> --version <version>
```

<br/>

## Documentation

| Document | Applies to |
|---|---|
| [HA Rolling Upgrade Verification](docs/ha-rolling-verification.md) | `elasticsearch-eck`, `kibana-eck` — evidence that rolling upgrades are zero-downtime in HA topology (chart 0.1.1 / Stack 9.3.3) |

<br/>

## Releasing

Charts are released automatically when a `Chart.yaml` `version` bump is merged to `main`.

1. Bump `version` in `charts/<chart>/Chart.yaml`.
2. Open a PR. CI runs `helm lint` and `chart-testing` on changed charts.
3. After merge, [chart-releaser-action](https://github.com/helm/chart-releaser-action) packages the chart, creates a GitHub Release tagged `<chart>-<version>`, and updates the `gh-pages` index. The same tarball is also pushed to GHCR as an OCI artifact.

<br/>

## Contributing

PRs welcome. Please:

- Bump the chart `version` in `Chart.yaml` for any change to chart contents.
- Update the chart's `README.md` if values or behavior change.
- Verify locally with `helm lint charts/<chart>` and `helm template charts/<chart>`.

<br/>

## License

[Apache-2.0](LICENSE)
