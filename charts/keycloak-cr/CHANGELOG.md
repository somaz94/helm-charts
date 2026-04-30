# Changelog

All notable changes to this chart will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [v0.1.0] - 2026-04-30

### Added
- Initial release. Keycloak CR (k8s.keycloak.org/v2beta1) with hostname/db/http/proxy/scheduling/resources surfaced explicitly, KeycloakRealmImport with inline-spec or ConfigMap source, optional HTTPRoute, optional DB credentials Secret, optional bootstrap admin Secret, escape-hatch keycloakSpecExtra/realmSpecExtra blocks. Pure CR wrapper — requires the Keycloak Operator and CRDs to be installed in the cluster (e.g. via the keycloak-operator chart).
