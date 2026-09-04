# Changelog

All notable changes to this chart will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [v0.1.5] - 2026-09-04

### Changed
- Bump appVersion from 8.0.43 to 8.0.46

## [v0.1.4] - 2026-08-14

### Fixed
- A chart version bump no longer restarts the database. The checksum/config and checksum/secret pod annotations hashed the whole rendered ConfigMap and Secret, which carry a helm.sh/chart label containing the chart version, so every release changed them and rolled the pod — and with strategy Recreate that is downtime, not a rolling swap. They now hash only the data / stringData payload, so they move when the config or the credentials move and stay put otherwise.

## [v0.1.3] - 2026-08-14

### Added
- Backup CronJob now verifies the dump before counting it as a success, checking for the mysqldump "Dump completed" trailer. A dump cut short by a full disk, a dropped connection or an OOM previously exited zero and was retained, and on an --all-databases dump the file is large enough that size alone reveals nothing.

### Fixed
- Backup CronJob no longer leaves an empty .sql behind when mysqldump fails outright. The output redirect created the file before mysqldump ran, and set -e then exited before anything could clean it up, so a failed run left a 0-byte dump that reads as real when listing the backup directory. Cleanup now runs from a trap that is disarmed only after the dump passes verification.

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
