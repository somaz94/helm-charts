# Changelog

All notable changes to this chart will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [v0.1.2] - 2026-07-13

### Changed
- Refactor templates — split Service and PVC into dedicated service.yaml and pvc.yaml (one file per kind), and hoist reusable service/persistence shapes into schema $defs. Rendered output is unchanged.

## [v0.1.1] - 2026-07-06

### Added
- Add checksum/config and checksum/secret pod annotations so ConfigMap or Secret changes trigger a rollout on helm upgrade.

## [v0.1.0] - 2026-04-30

### Added
- Initial release. Standalone single-node MySQL 8 with ConfigMap (custom.cnf), Secret, PVC, Deployment (Recreate strategy), Service (ClusterIP/NodePort), optional backup CronJob (mysqldump + retention), NetworkPolicy, ServiceAccount, image pull Secret (chart-managed dockerconfigjson + BYOIPS, additive), kubernetesExtra escape hatch.
- `auth.existingSecret` + `auth.secretKeys.{user,password,rootPassword,database}` for adopting legacy Secrets that use non-standard key names (e.g. `DB_USERNAME` instead of `MYSQL_USER`) without re-keying.
- `fullnameOverride` and `configMap.nameOverride` to adopt pre-existing resources whose names do not fit the chart default (typical when migrating off raw-YAML deployments).
- `persistence.existingClaim` for PVC reuse — the chart will not render or modify the PVC when set, preserving the underlying volume on uninstall.
