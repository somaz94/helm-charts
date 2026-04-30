# Changelog

All notable changes to this chart will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [v0.1.4] - 2026-04-30

### Changed
- Bump appVersion from 5.117.0 to 5.130.6

## [v0.1.3] - 2026-04-30

### Added
- Initial release. Ghost Deployment with optional bundled MySQL (ConfigMap, Secret, PVC, Deployment, Service), backup CronJob, HTTPRoute (Gateway API), Ingress, NGINX Gateway Fabric ClientSettingsPolicy and Prometheus ServiceMonitor.
- `mysql.fullnameOverride` and `mysql.configMap.nameOverride` to control the MySQL Deployment/Service/ConfigMap/Secret base names. Lets users adopt pre-existing resources whose names do not match the default `<fullname>-mysql` pattern (typical when migrating off legacy raw-YAML deployments).
- `imagePullSecret.{create,name,dockerconfigjson}` for chart-managed `kubernetes.io/dockerconfigjson` Secret rendering. Combines with `imagePullSecrets[]` (BYOIPS, additive). Lets users pull from a private registry with a single chart install instead of hand-managing the Secret.

### Changed
- `backup.image.{repository,tag,pullPolicy}` now default to `mysql.image.*` when left empty (DRY). Bumping `mysql.image.tag` auto-syncs the backup CronJob image. Set `backup.image.*` explicitly to pin a different client.
- `ghost.mysql.secretName` and `ghost.mysql.configMapName` helpers now derive from `ghost.mysql.fullname` instead of inlining the `<fullname>-mysql` pattern. No effect on default users; enables the new overrides above to propagate consistently.
- Pod-spec `imagePullSecrets:` rendering moved into a single `ghost.imagePullSecretsBlock` helper used by Ghost Deployment, MySQL Deployment and backup CronJob. Default behavior unchanged when `imagePullSecret.create` is false.

### Fixed
- `.helmignore` now excludes `upgrade.sh`, `backup/` and `ci/` from packaged chart tarballs (chart-maintainer tooling + CI values should not ship to consumers).
