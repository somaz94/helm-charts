# Changelog

All notable changes to this chart will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [v0.1.0] - 2026-10-19

### Added
- Initial release: KEDA-scaled SQS consumer Deployment with scale to zero, an aws-sqs-queue ScaledObject, a podIdentity TriggerAuthentication (identityOwner workload / keda, or an explicit roleArn), an IRSA-ready ServiceAccount, and a plain-Deployment mode when keda.enabled is false.
