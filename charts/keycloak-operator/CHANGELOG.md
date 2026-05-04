# Changelog

All notable changes to this chart will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [v0.1.3] - 2026-05-04

### Fixed
- Quote artifacthub.io/changes descriptions so chart-releaser/ArtifactHub linter accepts the prior release content (unquoted form failed annotation validation).

## [v0.1.2] - 2026-04-30

### Changed
- Sync upgrade.sh from canonical helm-charts/external-tracked template (RESET annotation model + JSON dry-run schema v1).

## [v0.1.1] - 2026-04-30

### Added
- rbac.useClusterBindings option (default false) to bind keycloakcontroller-cluster-role and keycloakrealmimportcontroller-cluster-role via ClusterRoleBinding instead of in-namespace RoleBinding. Required for any cross-namespace watchNamespaces value because RoleBindings only grant their bound rules within their own namespace, so the operator silently 403s on list/watch in other namespaces otherwise.

### Changed
- Documented the correct Quarkus Operator SDK constants for watchNamespaces — JOSDK_WATCH_CURRENT (own ns) and JOSDK_ALL_NAMESPACES (cluster-wide). The previous JOSDK_WATCH_ALL example was not a valid constant and the operator interpreted that string as a namespace name, returning 403 on startup.
