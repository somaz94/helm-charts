# Changelog

All notable changes to this chart will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [v0.2.1] - 2026-04-30

### Changed
- Add ci/install-values.yaml for kubeconform/chart-testing CI coverage.

## [v0.2.0] - 2026-04-30

### Added
- Optional `ingresses[]` block — emits Ingress resources alongside the Certificate for the one-shot install pattern (cert-manager.io/cluster-issuer annotation already wired up).
- Per-provider end-to-end examples (Cloudflare, AWS Route53, Google Cloud DNS) in README — secret + ClusterIssuer + Certificate + Ingress in one values file.
