# Changelog

All notable changes to this chart will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [v0.2.4] - 2026-07-06

### Changed
- Make `email` optional for `clusterIssuers[]` and `issuers[]` — ACME / cert-manager does not require an email. The `email` field is now omitted from the rendered ClusterIssuer/Issuer when not set.

## [v0.2.3] - 2026-07-06

### Changed
- Add app.kubernetes.io/name and app.kubernetes.io/version to the common label set for standard-label consistency across the chart collection.

## [v0.2.2] - 2026-05-04

### Fixed
- Quote artifacthub.io/changes descriptions so chart-releaser/ArtifactHub linter accepts the prior release content (unquoted form failed annotation validation).

## [v0.2.1] - 2026-04-30

### Changed
- Add ci/install-values.yaml for kubeconform/chart-testing CI coverage.

## [v0.2.0] - 2026-04-30

### Added
- Optional `ingresses[]` block — emits Ingress resources alongside the Certificate for the one-shot install pattern (cert-manager.io/cluster-issuer annotation already wired up).
- Per-provider end-to-end examples (Cloudflare, AWS Route53, Google Cloud DNS) in README — secret + ClusterIssuer + Certificate + Ingress in one values file.
