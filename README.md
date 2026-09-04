# helm-charts

> Production-ready Helm charts for Kubernetes — MySQL, PostgreSQL, Redis, Keycloak, Elasticsearch/Kibana (ECK), MetalLB, Karpenter, cert-manager, Ghost & more. Published to a classic Helm repo, GHCR OCI registry, and ArtifactHub.

A collection of Helm charts maintained by [@somaz94](https://github.com/somaz94).

Charts are published to:

- **Helm repo** (classic): `https://charts.somaz.blog`
- **GHCR** (OCI registry): `oci://ghcr.io/somaz94/charts/<chart-name>`

<br/>

## Charts

The latest released version of each chart is published to the channels listed under [Install](#install) — `helm repo update && helm search repo somaz94/<chart>`, the `oci://ghcr.io/somaz94/charts/<chart>` registry tags, and the GitHub Releases tagged `<chart>-<version>`.

| Chart | Description |
|---|---|
| [nginx-gateway-cr](charts/nginx-gateway-cr) | Custom resources for NGINX Gateway Fabric — Gateway, NginxProxy, ReferenceGrant, ClientSettingsPolicy, plus ServiceMonitor / PodMonitor for Prometheus |
| [prometheus-cr](charts/prometheus-cr) | Custom resources for the Prometheus Operator — data-driven ServiceMonitor / PodMonitor / PrometheusRule / Probe / ScrapeConfig rendered from list-valued inputs. Closes the gap where kube-prometheus-stack installs the CRDs but leaves app-level monitoring CRs to each consumer. Safe empty defaults (no-op install). |
| [metallb-cr](charts/metallb-cr) | Custom resources for MetalLB — data-driven IPAddressPool, L2Advertisement, BGPAdvertisement, BGPPeer, Community, BFDProfile rendered from list-valued inputs. Closes the gap where the upstream `metallb/metallb` chart intentionally does not template config CRs (replaces the out-of-band `kubectl apply` hook). Safe empty defaults (no-op install). |
| [karpenter-cr](charts/karpenter-cr) | Custom resources for AWS Karpenter — data-driven EC2NodeClass + NodePool (multi-pool, shared defaults with per-entry override). Discovery-tag subnet / SG selection, secure-by-default, AMI selection required (no silent drift). Karpenter v1 API, self-managed controller or EKS Auto Mode. |
| [aws-storageclass](charts/aws-storageclass) | Data-driven AWS StorageClass objects — EBS and EFS — rendered from a single list, each entry individually toggleable. Closes the gap where the AWS CSI drivers install the provisioner but do not create StorageClasses. Safe empty defaults (no-op install). |
| [certmanager-letsencrypt](charts/certmanager-letsencrypt) | Let's Encrypt resources for cert-manager — multi-issuer / multi-certificate / multi-secret / optional Ingress, DNS-01 (Cloudflare, Route53, Cloud DNS, ...) |
| [external-secrets-cr](charts/external-secrets-cr) | Custom resources for the External Secrets Operator — data-driven SecretStore / ClusterSecretStore / ExternalSecret / ClusterExternalSecret / PushSecret rendered from list-valued inputs, with verbatim provider pass-through. Closes the gap where the upstream external-secrets chart installs the operator + CRDs but does not template config CRs. Safe empty defaults (no-op install). |
| [elasticsearch-eck](charts/elasticsearch-eck) | Elasticsearch CR for ECK (Elastic Cloud on Kubernetes) — multi-nodeSet topology, HTTPRoute, Ingress, BackendTLSPolicy, PDB, ServiceMonitor, NetworkPolicy, ReferenceGrant, sysctl init container. Single-node default, HA opt-in. |
| [kibana-eck](charts/kibana-eck) | Kibana CR for ECK — auto-wired to an Elasticsearch CR via `elasticsearchRef`, HTTPRoute, Ingress, BackendTLSPolicy, PDB, ServiceMonitor, NetworkPolicy, ReferenceGrant. Sibling-version check in `upgrade.sh`. |
| [ghost](charts/ghost) | Ghost CMS (Node.js blog) — Deployment + PVC, optional bundled MySQL, backup CronJob, HTTPRoute + NGF ClientSettingsPolicy, Ingress, ServiceMonitor. Name/claim overrides for adopting legacy resources, and a chart-managed image pull Secret. Suits self-hosted single-replica blogs. |
| [unity-mcp-server](charts/unity-mcp-server) | Unity MCP (Model Context Protocol) Server running FastMCP's StreamableHTTP transport — Deployment + Service + optional API-key Secret, HTTPRoute + NGF ProxySettingsPolicy (SSE-friendly), Ingress. Bring-your-own-image (build from CoplayDev/unity-mcp), with a chart-managed pull Secret for private registries. |
| [mysql](charts/mysql) | Standalone single-node MySQL — Deployment + ConfigMap + Secret + PVC + Service, optional backup CronJob (mysqldump + retention), NetworkPolicy, ServiceAccount, image pull Secret. Existing-Secret and name/claim overrides for adopting legacy resources and in-place migration off raw-YAML deployments. Suits dev/staging single-replica installs. |
| [postgresql](charts/postgresql) | Standalone single-node PostgreSQL — Deployment + ConfigMap + Secret + PVC + Service, optional backup CronJob (`pg_dump` / `pg_dumpall` + retention), NetworkPolicy, ServiceAccount, image pull Secret, log emptyDir for `logging_collector` workloads. Existing-Secret and name overrides for in-place migration off raw-YAML deployments. |
| [redis](charts/redis) | Standalone single-node Redis — Deployment + PVC + Service, optional auth Secret and `redis.conf` ConfigMap, NetworkPolicy, ServiceAccount, image pull Secret. Mount-path / existing-claim / name overrides for in-place migration off raw-YAML deployments. |
| [keycloak-operator](charts/keycloak-operator) | Keycloak Operator install (CRDs + Deployment + RBAC + Service) wrapped from the upstream `keycloak/keycloak-k8s-resources` raw YAML — the Keycloak project does not publish an official Helm chart for the operator. `upgrade.sh` tracks new k8s-resources tags and refreshes the in-tree CRD templates. Configurable operator / server image, watched namespaces, and CRD install / keep policy. |
| [keycloak-cr](charts/keycloak-cr) | Custom resources for the Keycloak Operator — `Keycloak` with hostname / db / proxy / scheduling / resources / features / tracing surfaced explicitly, plus `KeycloakRealmImport` with inline RealmRepresentation. Optional HTTPRoute, standalone Ingress, DB-credentials and bootstrap-admin Secrets, and a `specExtra` escape hatch. Pure CR wrapper — requires the `keycloak-operator` chart (or upstream raw YAML) installed first. |
| [buildkit](charts/buildkit) | Standalone BuildKit StatefulSet — `moby/buildkit` pod (rootful, privileged) with optional registry CA-bundle Secret and `buildkitd.toml` ConfigMap, cache PVC via `volumeClaimTemplates`, ClusterIP Service. Auto-renders a minimal `buildkitd.toml` wiring the registry CA when one is supplied. Suits in-cluster `docker buildx` consumers (kubernetes/remote driver) needing multi-arch builds against a self-signed registry. |

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
| [HA Rolling Upgrade Verification](docs/ha-rolling-verification.md) | `elasticsearch-eck`, `kibana-eck` — evidence that rolling upgrades are zero-downtime in HA topology; the doc header records the chart and Stack versions it was verified against |
| [Maintainer scripts overview](scripts/README.md) | everything under [`scripts/`](scripts/) — how the maintainer sub-systems collaborate (template propagation → drift detection → CHANGELOG render → validation gates) and the file-level contracts between them |

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
