# Changelog

All notable changes to this chart will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [v0.1.0] - 2026-07-21

### Added
- Initial release: data-driven AWS StorageClass chart. Renders any number of
  `storage.k8s.io/v1` StorageClass objects (EBS gp3/gp2/io2, EFS, ...) from a
  single `storageClasses[]` list, each entry individually toggleable via `enabled`.
- Per-entry `isDefault` marks the cluster default class
  (`storageclass.kubernetes.io/is-default-class`), plus `parameters`,
  `volumeBindingMode`, `reclaimPolicy`, `allowVolumeExpansion`, `mountOptions`,
  `allowedTopologies`, and per-entry `labels` / `annotations`.
- Shared `commonLabels` / `commonAnnotations` and a per-entry `parametersExtra`
  escape hatch for unsurfaced CSI parameters.
- Safe empty default (no-op install), a `values.schema.json` contract
  (`additionalProperties: false` at root), and `ci/install-values.yaml`
  exercising EBS + EFS rendering for chart-testing / kubeconform coverage.
