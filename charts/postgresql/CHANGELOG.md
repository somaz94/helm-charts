# Changelog

All notable changes to this chart will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [v0.1.4] - 2026-08-14

### Fixed
- Backup CronJob no longer leaves an empty .sql behind when pg_dump fails outright. The output redirect created the file before pg_dump ran, and set -e then exited past the cleanup, so a failed run left a 0-byte dump that reads as real when listing the backup directory. Cleanup now runs from a trap that is disarmed only after the dump passes verification.

## [v0.1.3] - 2026-08-10

### Changed
- Refactor templates — split Service and PVC into dedicated service.yaml and pvc.yaml (one file per kind), and hoist reusable service/persistence shapes into schema $defs. Rendered output is unchanged.

## [v0.1.2] - 2026-07-13

### Changed
- Refactor templates — split Service and PVC into dedicated service.yaml and pvc.yaml (one file per kind), and hoist reusable service/persistence shapes into schema $defs. Rendered output is unchanged.

## [v0.1.1] - 2026-07-06

### Added
- Add checksum/config and checksum/secret pod annotations so ConfigMap or Secret changes trigger a rollout on helm upgrade.

## [v0.1.0] - 2026-04-30

### Added
- Initial release. Standalone single-node PostgreSQL with ConfigMap (postgresql.conf + pg_hba.conf), Secret, PVC, Deployment (Recreate strategy), Service (ClusterIP/NodePort), optional backup CronJob (pg_dump + retention), NetworkPolicy, ServiceAccount, image pull Secret (chart-managed dockerconfigjson + BYOIPS), log emptyDir for logging_collector, kubernetesExtra escape hatch.
- `auth.existingSecret` + `auth.secretKeys.{user,password,database}` for adopting legacy Secrets that use non-standard key names (e.g. `DB_USERNAME` instead of `POSTGRES_USER`) without re-keying.
- `fullnameOverride` and `configMap.nameOverride` to adopt pre-existing resources whose names do not fit the chart default (typical when migrating off raw-YAML deployments).
- `persistence.existingClaim` for PVC reuse — the chart will not render or modify the PVC when set, preserving the underlying volume on uninstall.
- `logCollector.enabled` toggles the `/var/log/postgresql` emptyDir mount for logging_collector=on workloads (default off — stderr to stdout).
