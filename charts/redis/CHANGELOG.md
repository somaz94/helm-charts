# Changelog

All notable changes to this chart will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [v0.1.0] - 2026-04-30

### Added
- Initial release. Standalone single-node Redis with optional ConfigMap (redis.conf), optional Secret (auth password), PVC, Deployment (Recreate strategy), Service (ClusterIP/NodePort), NetworkPolicy, ServiceAccount, image pull Secret (chart-managed dockerconfigjson + BYOIPS), kubernetesExtra escape hatch. Default image tracks Redis 8.2 (RSALv2/SSPL); pin `image.tag: 7.4-alpine` to remain on the last BSD-licensed release.
- `auth.existingSecret` + `auth.passwordKey` for adopting legacy Secrets that hold the Redis password under non-standard keys.
- `fullnameOverride` and `configMap.nameOverride` to adopt pre-existing resources whose names do not fit the chart default.
- `persistence.{enabled,existingClaim,mountPath}` for PVC reuse and non-standard mount paths (e.g. `/redis-master-data` from legacy raw YAML).
