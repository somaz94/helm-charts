# Changelog

All notable changes to this chart will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [v0.2.0] - 2026-08-31

### Added
- Support EKS Auto Mode: nodeClassGroup / nodeClassKind select the node class API a NodePool binds to (eks.amazonaws.com/NodeClass), settable per pool or in nodePoolDefaults. Defaults are unchanged, so self-managed Karpenter values render byte-identically.
- Add terminationGracePeriod to NodePool entries and nodePoolDefaults, so a pool can cap how long a node may take to drain.

## [v0.1.2] - 2026-07-06

### Changed
- Add app.kubernetes.io/name and app.kubernetes.io/version to the common label set for standard-label consistency across the chart collection.

## [v0.1.1] - 2026-06-24

### Added
- Set artifacthub.io/category to integration-delivery for ArtifactHub classification.

## [v0.1.0] - 2026-06-12

### Added
- Initial release: data-driven `EC2NodeClass` + `NodePool` custom resources for AWS Karpenter.
- Multi-pool rendering from `nodeClasses` / `nodePools` lists with shared `*Defaults` blocks and per-entry override.
- Discovery-tag subnet / security-group selection (`<discoveryKey> = <clusterName>`) with per-entry explicit selector override.
- `values.schema.json` contract (`additionalProperties: false`) and `ci/install-values.yaml` for chart-testing / kubeconform coverage.
