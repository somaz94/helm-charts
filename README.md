# helm-charts

A collection of Helm charts maintained by [@somaz94](https://github.com/somaz94).

Charts are published to:

- **Helm repo** (classic): `https://charts.somaz.blog`
- **GHCR** (OCI registry): `oci://ghcr.io/somaz94/charts/<chart-name>`

<br/>

## Charts

The latest released version of each chart is published to the channels listed under [Install](#install) — `helm repo update && helm search repo somaz94/<chart>`, the `oci://ghcr.io/somaz94/charts/<chart>` registry tags, and the GitHub Releases tagged `<chart>-<version>`.

| Chart | Description |
|---|---|
| [nginx-gateway-cr](charts/nginx-gateway-cr) | Custom resources for NGINX Gateway Fabric — Gateway, NginxProxy, ReferenceGrant, plus ServiceMonitor / PodMonitor for Prometheus |
| [certmanager-letsencrypt](charts/certmanager-letsencrypt) | Let's Encrypt resources for cert-manager — multi-issuer / multi-certificate / multi-secret / optional Ingress, DNS-01 (Cloudflare, Route53, Cloud DNS, ...) |
| [elasticsearch-eck](charts/elasticsearch-eck) | Elasticsearch CR for ECK (Elastic Cloud on Kubernetes) — nodeSets[] array, HTTPRoute, Ingress, BackendTLSPolicy, PDB (native/external), ServiceMonitor, NetworkPolicy, ReferenceGrant, sysctl init container. Single-node default, HA opt-in. |
| [kibana-eck](charts/kibana-eck) | Kibana CR for ECK — auto-wired to an Elasticsearch CR via elasticsearchRef, HTTPRoute, Ingress, BackendTLSPolicy, PDB, ServiceMonitor, NetworkPolicy, ReferenceGrant. Sibling-version check in upgrade.sh. |
| [ghost](charts/ghost) | Ghost CMS (Node.js blog) — Deployment + PVC + optional bundled MySQL 8 (ConfigMap/Secret/PVC/Deployment/Service), backup CronJob, HTTPRoute + NGF ClientSettingsPolicy, Ingress, ServiceMonitor. `mysql.fullnameOverride` / `mysql.configMap.nameOverride` for adopting legacy resources. `imagePullSecret.create + dockerconfigjson` for chart-managed pull Secret. Suits self-hosted single-replica blogs. |
| [unity-mcp-server](charts/unity-mcp-server) | Unity MCP (Model Context Protocol) Server running FastMCP's StreamableHTTP transport — Deployment + Service + optional API-key Secret, HTTPRoute + NGF ProxySettingsPolicy (SSE-friendly), Ingress. Bring-your-own-image (build from CoplayDev/unity-mcp). `imagePullSecret.create + dockerconfigjson` for chart-managed pull Secret when the BYOI image lives in a private registry. |
| [mysql](charts/mysql) | Standalone single-node MySQL 8 — Deployment + ConfigMap (`custom.cnf`) + Secret + PVC + Service, optional backup CronJob (mysqldump + retention), NetworkPolicy, ServiceAccount, image pull Secret (chart-managed + BYOIPS). `auth.existingSecret` + `auth.secretKeys.*` for adopting legacy Secrets with non-standard key names (`DB_USERNAME` etc). `fullnameOverride` + `configMap.nameOverride` + `persistence.existingClaim` for in-place migration off raw-YAML deployments. Suits dev/staging single-replica installs. |
| [postgresql](charts/postgresql) | Standalone single-node PostgreSQL — Deployment + ConfigMap (`postgresql.conf` + `pg_hba.conf`) + Secret + PVC + Service, optional backup CronJob (`pg_dump` / `pg_dumpall` + retention), NetworkPolicy, ServiceAccount, image pull Secret, log emptyDir for `logging_collector` workloads. `auth.existingSecret` + `auth.secretKeys.*` + `pgData` + `fullnameOverride` for in-place migration off raw-YAML deployments. |
| [redis](charts/redis) | Standalone single-node Redis — Deployment + PVC + Service, optional Secret (auth password), optional ConfigMap (`redis.conf`), NetworkPolicy, ServiceAccount, image pull Secret. `persistence.mountPath` + `persistence.existingClaim` + `fullnameOverride` for in-place migration off raw-YAML deployments (e.g. legacy `/redis-master-data` mount). Sibling to `valkey-cr`. |
| [keycloak-operator](charts/keycloak-operator) | Keycloak Operator install (CRDs + Deployment + RBAC + Service) wrapped from the upstream `keycloak/keycloak-k8s-resources` raw YAML — the Keycloak project does not publish an official Helm chart for the operator. `upgrade.sh` tracks new k8s-resources tags and refreshes the in-tree `templates/crd-*.yaml`. Configurable image / `serverImage` (RELATED_IMAGE_KEYCLOAK) / `watchNamespaces` (current / all / list). `crds.install` + `crds.keep` for externally-managed or uninstall-survivable CRDs. |
| [keycloak-cr](charts/keycloak-cr) | Custom resources for the Keycloak Operator — `Keycloak` (k8s.keycloak.org/v2beta1) with hostname/db/proxy/scheduling/resources/features/tracing surfaced explicitly + `KeycloakRealmImport` with inline RealmRepresentation. Optional HTTPRoute (Gateway API) + standalone Ingress + DB-credentials Secret + bootstrap-admin Secret. Escape-hatch `keycloak.specExtra` / `realmImport.specExtra` for unsurfaced fields. Pure CR wrapper — requires the `keycloak-operator` chart (or upstream raw YAML) installed first. |

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
| [Maintainer scripts overview](scripts/README.md) | `scripts/upgrade-sync/`, `scripts/check-version/`, `scripts/changelog/` — how the three sub-systems collaborate (template propagation → drift detection → CHANGELOG render) and the contracts between them |

<br/>

## Prerequisites

Maintainers and local builders need:

- Helm 3.16+
- bash ≥ 4 (Homebrew bash on macOS)
- python3 (used by `scripts/`)
- Optional: `chart-testing`, `kubeconform`, `gh` for full `make ci` and auto-bump PRs

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
