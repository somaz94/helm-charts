# Security Policy

## Supported Versions

Each chart is independently versioned. Only the **latest released version** of each chart receives security fixes. Users are encouraged to track the latest release and bump promptly when security advisories are published.

The current latest version of every chart below is published to:

- OCI registry: `oci://ghcr.io/somaz94/charts/<chart>` (resolve `:latest` or pin a tag)
- Classic Helm repo: `https://charts.somaz.blog` (run `helm repo update` then `helm search repo somaz94/<chart>`)
- GitHub Releases: tagged `<chart>-<version>` per release

Charts in scope:

| Chart |
|---|
| certmanager-letsencrypt |
| elasticsearch-eck |
| ghost |
| keycloak-operator |
| kibana-eck |
| mysql |
| nginx-gateway-cr |
| postgresql |
| redis |
| unity-mcp-server |

## Reporting a Vulnerability

If you discover a security vulnerability in any chart in this repository, **please do not open a public issue.** Instead, report it privately so that a fix can be prepared before the issue becomes public.

### Preferred channel: GitHub Security Advisories

Use the **"Report a vulnerability"** button on the [Security tab](https://github.com/somaz94/helm-charts/security/advisories/new) of this repository. This opens a private advisory visible only to maintainers.

### Alternative channel: email

Send a private email to **genius5711@gmail.com** with subject prefixed `[helm-charts security]`. Include:

- Affected chart name and version
- Steps to reproduce
- Impact assessment (what an attacker could achieve)
- Any suggested mitigation

## Response expectations

- **Acknowledgement**: within 7 days of report
- **Initial assessment**: within 14 days
- **Fix release**: timeline depends on severity, typically within 30 days for high/critical issues

## Disclosure

Once a fix is released, the advisory will be published on the GitHub Security Advisories page and an entry will be added to the affected chart's `artifacthub.io/changes` with `kind: security`.

## Scope

This policy covers:
- Helm chart templates that produce insecure or vulnerable Kubernetes manifests
- `values.yaml` defaults that expose unintended attack surface
- CI / release workflow vulnerabilities affecting chart integrity

Out of scope:
- Vulnerabilities in upstream projects this chart references (e.g. NGINX Gateway Fabric itself) — please report to the upstream maintainers
- Vulnerabilities in user-supplied configurations (`values.yaml` overrides)
