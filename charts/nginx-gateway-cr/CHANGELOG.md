# Changelog

All notable changes to this chart will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [v0.3.1] - 2026-04-30

### Changed
- Add ci/install-values.yaml for kubeconform/chart-testing CI coverage; set https.tlsSecretName in CI values to satisfy the Gateway listener schema (kubeconform fix).

## [v0.3.0] - 2026-04-30

### Added
- PodMonitor templates (controller + dataplane) — recommended for NGF 2.x where the controller exposes /metrics on the Pod, not the Service
- podMonitor.controller / podMonitor.dataplane values blocks (mirror serviceMonitor.* shape)
