# helm-charts

A collection of Helm charts maintained by [@somaz94](https://github.com/somaz94).

Charts are published to:

- **Helm repo** (classic): `https://charts.somaz.blog`
- **GHCR** (OCI registry): `oci://ghcr.io/somaz94/charts/<chart-name>`

## Charts

| Chart | Version | Description |
|---|---|---|
| [nginx-gateway-cr](charts/nginx-gateway-cr) | `0.2.0` | Custom resources (Gateway, NginxProxy, ServiceMonitor) for NGINX Gateway Fabric |

## Install

### Classic Helm repo

```bash
helm repo add somaz94 https://charts.somaz.blog
helm repo update
helm search repo somaz94
helm install <release> somaz94/<chart-name>
```

### OCI registry (Helm 3.8+)

```bash
helm install <release> oci://ghcr.io/somaz94/charts/<chart-name> --version <version>
```

## Releasing

Charts are released automatically when a `Chart.yaml` `version` bump is merged to `main`.

1. Bump `version` in `charts/<chart>/Chart.yaml`.
2. Open a PR. CI runs `helm lint` and `chart-testing` on changed charts.
3. After merge, [chart-releaser-action](https://github.com/helm/chart-releaser-action) packages the chart, creates a GitHub Release tagged `<chart>-<version>`, and updates the `gh-pages` index. The same tarball is also pushed to GHCR as an OCI artifact.

## Contributing

PRs welcome. Please:

- Bump the chart `version` in `Chart.yaml` for any change to chart contents.
- Update the chart's `README.md` if values or behavior change.
- Verify locally with `helm lint charts/<chart>` and `helm template charts/<chart>`.

## License

[Apache-2.0](LICENSE)
