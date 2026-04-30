# Changelog

All notable changes to this chart will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [v0.1.4] - 2026-04-30

### Changed
- Add ci/install-values.yaml for kubeconform/chart-testing CI coverage; sync upgrade.sh from canonical chart-appversion template (RESET annotation model + JSON dry-run schema v1).

## [v0.1.3] - 2026-04-30

### Added
- Initial release. Kibana ECK CR with podTemplate extensibility, HTTPRoute, legacy Ingress, PodDisruptionBudget, and elasticsearchRef auto-wiring.

### Changed
- BREAKING for non-NGF Gateway implementations. BackendTLSPolicy now references the ECK-managed Secret `<name>-kb-http-certs-public` directly via `caCertificateRefs`, eliminating the `lookup`-based CA ConfigMap copy. `helm diff` / `helmfile diff` now render deterministically. Migration: NGINX Gateway Fabric users — no action. Gateway API Core-only implementations (which do not support Secret kind in caCertificateRefs) — set `backendTLSPolicy.caCertificateRef.kind: ConfigMap` and provision the ConfigMap out-of-band.

### Removed
- The auto-generated `<name>-ca` ConfigMap. Existing installs will leave an orphaned ConfigMap — helm garbage-collects it on upgrade.

### Fixed
- Correct artifacthub.io/category to `monitoring-logging` (was `monitoring`, rejected by ArtifactHub).
- DO NOT USE 0.1.2 — same NGF Opaque Secret rejection as elasticsearch-eck 0.1.3. 0.1.3 reverts to the 0.1.1 behavior: `caCertificateRef.kind: ConfigMap` with chart-rendered CA ConfigMap via `helm lookup`. The `caCertificateRef` values block is retained for advanced consumers — `kind: Secret` requires a `kubernetes.io/tls`-typed Secret, or use consumer-managed external ConfigMap via `name: <custom>`. README documents the helm-diff lookup limitation as a known trade-off.
