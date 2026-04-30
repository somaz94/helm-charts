# Changelog

All notable changes to this chart will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [v0.1.0] - 2026-04-30

### Added
- Initial release. Standalone single-node PostgreSQL with ConfigMap (postgresql.conf + pg_hba.conf), Secret, PVC, Deployment (Recreate strategy), Service (ClusterIP/NodePort), optional backup CronJob (pg_dump + retention), NetworkPolicy, ServiceAccount, image pull Secret (chart-managed dockerconfigjson + BYOIPS), log emptyDir for logging_collector, kubernetesExtra escape hatch.
- `auth.existingSecret` + `auth.secretKeys.{user,password,database}` for adopting legacy Secrets that use non-standard key names (e.g. `DB_USERNAME` instead of `POSTGRES_USER`) without re-keying.
- `fullnameOverride` and `configMap.nameOverride` to adopt pre-existing resources whose names do not fit the chart default (typical when migrating off raw-YAML deployments).
- `persistence.existingClaim` for PVC reuse — the chart will not render or modify the PVC when set, preserving the underlying volume on uninstall.
- `logCollector.enabled` toggles the `/var/log/postgresql` emptyDir mount for logging_collector=on workloads (default off — stderr to stdout).
