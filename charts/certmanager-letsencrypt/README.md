# certmanager-letsencrypt

A Helm chart that manages [cert-manager](https://cert-manager.io/) Let's Encrypt resources — `ClusterIssuer` / `Issuer` / `Certificate` / DNS-01 credential `Secret` — in one place. **Requires cert-manager already installed.**

The upstream cert-manager chart installs the operator and CRDs, but does **not** create the tenant-level resources you actually issue certificates with. This chart fills that gap with a multi-issuer / multi-certificate / multi-secret schema.

## What it deploys

| Resource | API | Purpose |
|---|---|---|
| `Secret` | `v1` | Optional. Multiple credential secrets (DNS provider API tokens, service accounts, etc.) |
| `ClusterIssuer` | `cert-manager.io/v1` | Cluster-scoped ACME issuers (most common — one prod, one staging) |
| `Issuer` | `cert-manager.io/v1` | Namespace-scoped issuers (use for tenant isolation) |
| `Certificate` | `cert-manager.io/v1` | Per-domain certificate requests (cert-manager creates the actual TLS Secret) |

## Prerequisites

- Kubernetes **1.25+**
- [cert-manager](https://cert-manager.io/docs/installation/) installed (provides `cert-manager.io` CRDs)
- DNS provider account with API access (Cloudflare, Route53, Cloud DNS, ...) — DNS-01 challenge
- A registered domain whose DNS you control

## Install

### OCI registry (Helm 3.8+)

```bash
helm install cert oci://ghcr.io/somaz94/charts/certmanager-letsencrypt \
  --version 0.1.0 \
  --namespace cert-manager \
  -f my-values.yaml
```

### Classic Helm repo

```bash
helm repo add somaz94 https://charts.somaz.blog
helm repo update
helm install cert somaz94/certmanager-letsencrypt \
  --namespace cert-manager \
  -f my-values.yaml
```

## Quick examples

### Cloudflare DNS-01

```yaml
secrets:
  - name: cloudflare-api-token
    namespace: cert-manager
    type: Opaque
    stringData:
      api-token: "<your-cloudflare-api-token>"

clusterIssuers:
  - name: letsencrypt-prod
    email: ops@example.com
    server: https://acme-v02.api.letsencrypt.org/directory
    solvers:
      - dns01:
          cloudflare:
            apiTokenSecretRef:
              name: cloudflare-api-token
              key: api-token

  - name: letsencrypt-staging
    email: ops@example.com
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    solvers:
      - dns01:
          cloudflare:
            apiTokenSecretRef:
              name: cloudflare-api-token
              key: api-token

certificates:
  - name: example-com-tls
    namespace: default
    secretName: example-com-tls
    issuerRef:
      name: letsencrypt-prod
      kind: ClusterIssuer
    commonName: example.com
    dnsNames:
      - example.com
      - "*.example.com"
```

### AWS Route53 DNS-01

```yaml
secrets:
  - name: route53-credentials
    namespace: cert-manager
    type: Opaque
    stringData:
      secret-access-key: "<aws-secret-access-key>"

clusterIssuers:
  - name: letsencrypt-prod
    email: ops@example.com
    server: https://acme-v02.api.letsencrypt.org/directory
    solvers:
      - dns01:
          route53:
            region: us-east-1
            accessKeyID: "<aws-access-key>"
            secretAccessKeySecretRef:
              name: route53-credentials
              key: secret-access-key

certificates:
  - name: example-com-tls
    namespace: default
    secretName: example-com-tls
    issuerRef:
      name: letsencrypt-prod
      kind: ClusterIssuer
    dnsNames:
      - example.com
```

### Google Cloud DNS DNS-01

```yaml
secrets:
  - name: clouddns-credentials
    namespace: cert-manager
    type: Opaque
    data:
      key.json: "<base64-encoded-service-account-json>"

clusterIssuers:
  - name: letsencrypt-prod
    email: ops@example.com
    server: https://acme-v02.api.letsencrypt.org/directory
    solvers:
      - dns01:
          cloudDNS:
            project: "<gcp-project-id>"
            serviceAccountSecretRef:
              name: clouddns-credentials
              key: key.json

certificates:
  - name: example-com-tls
    namespace: default
    secretName: example-com-tls
    issuerRef:
      name: letsencrypt-prod
      kind: ClusterIssuer
    dnsNames:
      - example.com
```

## Values reference

### Top-level

| Key | Type | Default | Description |
|---|---|---|---|
| `commonLabels` | object | `{}` | Labels added to every resource. |
| `commonAnnotations` | object | `{}` | Annotations added to every resource. |
| `acmeServers.letsencryptProd` | string | LE prod URL | Production ACME endpoint (helper constant). |
| `acmeServers.letsencryptStaging` | string | LE staging URL | Staging ACME endpoint (helper constant). |

### `secrets[]`

| Key | Type | Required | Description |
|---|---|---|---|
| `name` | string | yes | Secret name. |
| `namespace` | string | yes | Namespace (typically `cert-manager`). |
| `type` | string | no | Default: `Opaque`. |
| `stringData` | object | one of | Plaintext key/value pairs. |
| `data` | object | one of | Pre-base64-encoded values. |

### `clusterIssuers[]` and `issuers[]`

`issuers[]` adds a required `namespace` field; otherwise identical.

| Key | Type | Required | Description |
|---|---|---|---|
| `name` | string | yes | Issuer name. |
| `email` | string | yes | ACME account email. |
| `server` | string | yes | ACME directory URL (use `acmeServers.letsencryptProd` etc.). |
| `privateKeySecretRef` | string | no | ACME account key secret name. Default: `<name>-account-key`. |
| `solvers` | list | yes | cert-manager solvers (DNS-01, HTTP-01) — passthrough. |

### `certificates[]`

| Key | Type | Required | Description |
|---|---|---|---|
| `name` | string | yes | Certificate name. |
| `namespace` | string | yes | Where the Certificate (and resulting TLS Secret) live. |
| `secretName` | string | yes | Name of the TLS Secret cert-manager will create. |
| `issuerRef` | object | yes | `{name, kind}` (`kind` = `ClusterIssuer` or `Issuer`). |
| `commonName` | string | no | Certificate Common Name. |
| `dnsNames` | list | no | SAN DNS names. |
| `uris` / `ipAddresses` / `emailAddresses` | list | no | Other SAN types. |
| `duration` | string | no | Default `2160h` (90d). |
| `renewBefore` | string | no | Default `720h` (30d). |
| `privateKey` | object | no | Algorithm/size override. |
| `usages` | list | no | Key usages (defaults from cert-manager). |
| `isCA` | bool | no | Mark cert as a CA. |
| `secretTemplate` | object | no | Labels/annotations on the resulting Secret. |

## Notes

### Ingress

This chart **does not create Ingress resources** — that's intentional. Ingresses are app-specific. The recommended pattern is to add the cert-manager annotation on your existing Ingress:

```yaml
metadata:
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  tls:
    - hosts:
        - example.com
      secretName: example-com-tls    # the secretName from your Certificate
```

cert-manager will see the annotation, look up the matching Certificate, and ensure the TLS Secret is in place.

### Use staging while iterating

Let's Encrypt production has strict rate limits (5 duplicate certs per week). When testing values, point your Certificate at the staging issuer first:

```yaml
certificates:
  - name: example-com-tls
    issuerRef:
      name: letsencrypt-staging
      kind: ClusterIssuer
    # ...
```

Once everything works end-to-end, switch `issuerRef.name` to the prod issuer.

## License

[Apache-2.0](../../LICENSE)
