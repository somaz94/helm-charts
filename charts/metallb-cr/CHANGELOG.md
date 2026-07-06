# Changelog

All notable changes to this chart will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [v0.1.1] - 2026-07-06

### Changed
- Add app.kubernetes.io/name and app.kubernetes.io/version to the common label set for standard-label consistency across the chart collection.

## [v0.1.0] - 2026-06-22

### Added
- Initial release: data-driven MetalLB configuration custom resources, deployed alongside the upstream metallb/metallb chart which intentionally does not template config CRs.
- IPAddressPool, L2Advertisement, BGPAdvertisement (metallb.io/v1beta1), BGPPeer (metallb.io/v1beta2), Community and BFDProfile rendered from list-valued inputs with shared commonLabels / commonAnnotations and a per-entry specExtra escape hatch.
- Safe empty defaults so an unconfigured install is a no-op, a values.schema.json contract (additionalProperties false at root), and ci/install-values.yaml exercising every template path for chart-testing / kubeconform coverage.
