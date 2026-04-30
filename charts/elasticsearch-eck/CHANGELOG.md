# Changelog

All notable changes to this chart will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [v0.1.4] - 2026-04-30

### Added
- Initial release. Elasticsearch ECK CR with nodeSets[] array, optional elastic-user Secret, HTTPRoute, BackendTLSPolicy, PodDisruptionBudget and ServiceMonitor.
- `caConfigMapName` helper restored in `_helpers.tpl`. `_helpers.tpl` comments clarify the ConfigMap source-of-truth relationship.

### Changed
- BREAKING for non-NGF Gateway implementations. BackendTLSPolicy now references the ECK-managed Secret `<name>-es-http-certs-public` directly via `caCertificateRefs`, eliminating the `lookup`-based CA ConfigMap copy. `helm diff` / `helmfile diff` now render deterministically. Migration: NGINX Gateway Fabric users — no action. Gateway API Core-only implementations (which do not support Secret kind in caCertificateRefs) — set `backendTLSPolicy.caCertificateRef.kind: ConfigMap` and provision the ConfigMap out-of-band (e.g. via Reflector or External Secrets).

### Removed
- Unused `elasticsearch-eck.resourceLabels` helper in `_helpers.tpl`. Dead code since 0.1.0 — templates use inline `with .Values.resourceMetadata.<key>.labels`. Pure refactor, zero functional change.
- The auto-generated `<name>-ca` ConfigMap and the `caConfigMapName` helper. Existing installs will leave an orphaned ConfigMap — safe to delete manually once BackendTLSPolicy is reconciled against the Secret.

### Fixed
- Correct artifacthub.io/category to `monitoring-logging` (was `monitoring`, rejected by ArtifactHub).
- DO NOT USE 0.1.3 — NGINX Gateway Fabric rejects `type: Opaque` Secrets for `caCertificateRefs`, so the 0.1.3 default (`kind: Secret`) breaks BTP resolution against ECK (which ships Opaque Secrets). 0.1.4 reverts to the 0.1.2 behavior: `caCertificateRef.kind: ConfigMap` with chart-rendered CA ConfigMap via `helm lookup`. The `caCertificateRef` values block is retained for advanced consumers — `kind: Secret` + `type: kubernetes.io/tls`, or consumer-managed external ConfigMap via `name: <custom>`. README documents the helm-diff lookup limitation as a known trade-off.
