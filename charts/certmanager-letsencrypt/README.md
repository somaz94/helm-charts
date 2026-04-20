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
  --version 0.2.0 \
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

Each per-provider example below is a **complete, end-to-end install**: credential `Secret` → `ClusterIssuer` (prod + staging) → `Certificate` → `Ingress` (with the cert-manager annotation pre-wired). Drop into a single values file and `helm install`.

> Use the **staging** issuer (`letsencrypt-staging`) while iterating to avoid Let's Encrypt rate limits, then switch `issuerRef.name` to `letsencrypt-prod` once everything works.

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

ingresses:
  - name: example-com-ingress
    namespace: default
    ingressClassName: nginx
    annotations:
      cert-manager.io/cluster-issuer: letsencrypt-prod
      nginx.ingress.kubernetes.io/rewrite-target: /
    rules:
      - host: example.com
        http:
          paths:
            - path: /
              pathType: Prefix
              backend:
                service:
                  name: my-app
                  port:
                    name: http
    tls:
      - hosts:
          - example.com
        secretName: example-com-tls
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

  - name: letsencrypt-staging
    email: ops@example.com
    server: https://acme-staging-v02.api.letsencrypt.org/directory
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

ingresses:
  - name: example-com-ingress
    namespace: default
    ingressClassName: nginx
    annotations:
      cert-manager.io/cluster-issuer: letsencrypt-prod
      nginx.ingress.kubernetes.io/rewrite-target: /
    rules:
      - host: example.com
        http:
          paths:
            - path: /
              pathType: Prefix
              backend:
                service:
                  name: my-app
                  port:
                    name: http
    tls:
      - hosts:
          - example.com
        secretName: example-com-tls
```

> For IRSA / IAM Roles for Service Accounts: omit `accessKeyID` and `secretAccessKeySecretRef`, use cert-manager's `serviceAccount` ServiceAccount referenced via `eks.amazonaws.com/role-arn` annotation. See [cert-manager Route53 docs](https://cert-manager.io/docs/configuration/acme/dns01/route53/).

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

  - name: letsencrypt-staging
    email: ops@example.com
    server: https://acme-staging-v02.api.letsencrypt.org/directory
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

ingresses:
  - name: example-com-ingress
    namespace: default
    ingressClassName: nginx
    annotations:
      cert-manager.io/cluster-issuer: letsencrypt-prod
      nginx.ingress.kubernetes.io/rewrite-target: /
    rules:
      - host: example.com
        http:
          paths:
            - path: /
              pathType: Prefix
              backend:
                service:
                  name: my-app
                  port:
                    name: http
    tls:
      - hosts:
          - example.com
        secretName: example-com-tls
```

> For Workload Identity (recommended on GKE): omit the JSON Secret, use `serviceAccountSecretRef`-less form with cert-manager pod's `iam.gke.io/gcp-service-account` annotation. See [cert-manager Cloud DNS docs](https://cert-manager.io/docs/configuration/acme/dns01/google/).

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

### `ingresses[]` (optional)

Optional. Most users keep Ingress in their app chart and just add a `cert-manager.io/cluster-issuer` annotation; this block exists for the one-shot install pattern (issuer + cert + ingress in one values file).

| Key | Type | Required | Description |
|---|---|---|---|
| `name` | string | yes | Ingress name. |
| `namespace` | string | yes | Ingress namespace (must match the Certificate's namespace if it shares the TLS Secret). |
| `labels` | object | no | Extra labels. |
| `annotations` | object | no | Extra annotations (typically `cert-manager.io/cluster-issuer: <issuer-name>`). |
| `ingressClassName` | string | no | Ingress class (e.g. `nginx`). |
| `rules` | list | no | Passthrough to `Ingress.spec.rules` (Kubernetes Ingress v1 schema). |
| `tls` | list | no | Passthrough to `Ingress.spec.tls`. `secretName` should match `certificates[].secretName`. |

## Notes

### Ingress

This chart can optionally create Ingress resources via the `ingresses[]` block (see examples above). It's **off by default** because most users keep Ingress in their app chart and only add the cert-manager annotation:

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

cert-manager sees the annotation, looks up the matching Certificate, and ensures the TLS Secret is in place. Use the `ingresses[]` block only when you want the chart to bundle the Ingress alongside the cert.

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
