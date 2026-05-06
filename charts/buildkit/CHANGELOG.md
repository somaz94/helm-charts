# Changelog

All notable changes to this chart will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [v0.1.0] - 2026-05-06

### Added
- Initial release. Standalone BuildKit StatefulSet with optional `buildkitd.toml` ConfigMap (registry trust + cache config), optional Secret (CA bundle for self-signed registries), `volumeClaimTemplates` cache PVC, ClusterIP Service (port 1234), NetworkPolicy, ServiceAccount, image pull Secret (chart-managed dockerconfigjson + BYOIPS), `kubernetesExtra` escape hatch. Default appVersion `v0.29.0`; container runs rootful with `securityContext.privileged: true` for cgroup mount (rootless mode left to a future toggle).
- `registry.caBundle.{enabled,existingSecret,key,host,ca,caPath}` for mounting a self-signed registry CA into BuildKit's trust store. When `existingSecret` is empty and `ca` is non-empty, the chart renders a Secret containing the CA file.
- `buildkitdConfig` opaque string mapped to `buildkitd.toml`. When empty AND `registry.caBundle.enabled` is true, the chart auto-renders a minimal config that wires the CA path. When empty AND CA bundle disabled, no ConfigMap is rendered (buildkitd runs with built-in defaults).
- `listener.unixSocket` + `listener.tcp.{enabled,port}` to control BuildKit's `--addr` flags. Default exposes both unix (for `docker buildx --driver kubernetes`) and TCP 1234 (for `--driver remote`).
