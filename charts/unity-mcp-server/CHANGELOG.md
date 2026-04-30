# Changelog

All notable changes to this chart will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [v0.1.5] - 2026-04-30

### Changed
- Sync upgrade.sh from canonical chart-appversion template (RESET annotation model + JSON dry-run schema v1).

## [v0.1.4] - 2026-04-30

### Changed
- Bump appVersion from 9.6.6 to 9.6.8

## [v0.1.3] - 2026-04-30

### Added
- Initial release. Deployment + Service + optional Secret (MCP API key), HTTPRoute (Gateway API), Ingress, and NGINX Gateway Fabric ProxySettingsPolicy (SSE buffering off) wrappers. Image is bring-your-own — see README.
- `imagePullSecret.{create,name,dockerconfigjson}` for chart-managed `kubernetes.io/dockerconfigjson` Secret rendering. Combines with `imagePullSecrets[]` (BYOIPS, additive). Useful when the BYOI image lives in a private registry.

### Changed
- `Chart.yaml` `appVersion` bumped from `3.0.0` (FastMCP library version, wrong) to `9.6.6` to match the upstream `CoplayDev/unity-mcp` release the chart was tested against. Aligns with what `upgrade.sh` (`github-release` source) reports.
- Pod-spec `imagePullSecrets:` rendering moved into a single `unity-mcp-server.imagePullSecretsBlock` helper. Default behavior unchanged when `imagePullSecret.create` is false.

### Fixed
- Replace hardcoded `v9.6.6` image tag in README and values.yaml examples with `YOUR_TAG` placeholder. The chart is bring-your-own-image — examples should not reference a specific upstream release that will go stale.
- `.helmignore` now excludes `upgrade.sh`, `backup/` and `ci/` from packaged chart tarballs (chart-maintainer tooling + CI values should not ship to consumers).
