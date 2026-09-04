# Changelog

All notable changes to this chart will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [v0.5.0] - 2026-09-04

### Added
- Support clientSettingsPolicies[].body.bufferSize (NGF 2.7.0+) to set client_body_buffer_size, above which a request body spills to a temporary file.

## [v0.4.0] - 2026-09-03

### Added
- Add clientSettingsPolicies[] rendering ClientSettingsPolicy resources, attachable to a Gateway, HTTPRoute or GRPCRoute and covering spec.body and spec.keepAlive.
- Support keepAlive.minTimeout (NGF 2.6.0+, nginx 1.27.4+) to hold idle keep-alive connections open across an nginx reload.

## [v0.3.3] - 2026-07-06

### Changed
- Add app.kubernetes.io/name and app.kubernetes.io/version to the common label set for standard-label consistency across the chart collection.

## [v0.3.2] - 2026-05-04

### Fixed
- Quote artifacthub.io/changes descriptions so chart-releaser/ArtifactHub linter accepts the 0.3.1 release content (the prior unquoted form failed annotation validation).

## [v0.3.1] - 2026-04-30

### Changed
- Add ci/install-values.yaml for kubeconform/chart-testing CI coverage; set https.tlsSecretName in CI values to satisfy the Gateway listener `certificateRefs.name` schema.

### Fixed
- Omit empty `hostname` from the Gateway https listener instead of emitting `hostname: ""` (Gateway v1 schema requires `minLength: 1`; a missing hostname is a valid catch-all).

## [v0.3.0] - 2026-04-30

### Added
- PodMonitor templates (controller + dataplane) — recommended for NGF 2.x where the controller exposes /metrics on the Pod, not the Service
- podMonitor.controller / podMonitor.dataplane values blocks (mirror serviceMonitor.* shape)
