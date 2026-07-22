# Changelog

All notable changes to this chart will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [v0.1.0] - 2026-07-22

### Added
- Initial release: data-driven Prometheus Operator monitoring custom resources, deployed alongside kube-prometheus-stack / prometheus-operator which installs the operator and CRDs but leaves app-level monitoring CRs to each consumer.
- ServiceMonitor, PodMonitor, PrometheusRule, Probe (monitoring.coreos.com/v1) and ScrapeConfig (monitoring.coreos.com/v1alpha1) rendered from list-valued inputs with shared commonLabels / commonAnnotations, per-entry namespace override, and a per-entry specExtra escape hatch.
- Safe empty defaults so an unconfigured install is a no-op, a values.schema.json contract (additionalProperties false at root), and ci/install-values.yaml exercising every template path for chart-testing / kubeconform coverage.
