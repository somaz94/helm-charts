# Changelog

All notable changes to this chart will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [v0.1.0] - 2026-07-22

### Added
- Initial release: data-driven External Secrets Operator configuration custom resources, deployed alongside the upstream external-secrets/external-secrets chart which installs the operator and CRDs but does not template config CRs.
- SecretStore, ClusterSecretStore, ExternalSecret, ClusterExternalSecret (external-secrets.io/v1) and PushSecret (external-secrets.io/v1alpha1) rendered from list-valued inputs with shared commonLabels / commonAnnotations, per-entry namespace override for namespaced kinds, and a per-entry specExtra escape hatch.
- Safe empty defaults so an unconfigured install is a no-op, a values.schema.json contract (additionalProperties false at root), and ci/install-values.yaml exercising every template path for chart-testing / kubeconform coverage.
