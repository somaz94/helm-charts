# Changelog

All notable changes to this chart will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [v0.1.0] - 2026-06-12

### Added
- Initial release: data-driven `EC2NodeClass` + `NodePool` custom resources for AWS Karpenter.
- Multi-pool rendering from `nodeClasses` / `nodePools` lists with shared `*Defaults` blocks and per-entry override.
- Discovery-tag subnet / security-group selection (`<discoveryKey> = <clusterName>`) with per-entry explicit selector override.
- `values.schema.json` contract (`additionalProperties: false`) and `ci/install-values.yaml` for chart-testing / kubeconform coverage.
