# schemas

<br/>

Repo-local JSON schemas for custom resources, consulted by `make validate`
before the remote datree `CRDs-catalog`.

<br/>

## Why this exists

`make validate` resolves CR schemas from the datree catalog. That catalog lags
upstream projects, so a chart can emit a perfectly valid CR whose schema is
simply absent. kubeconform then reports the resource as `statusSkipped` and —
because the run uses `-ignore-missing-schemas` — still exits 0. The resource
ships unvalidated.

Vendoring the schema here fixes that for one kind at a time. Local schemas take
precedence over the remote catalog, so this directory also lets you pin a kind
whose published entry is stale or wrong.

The alternative — declaring the kind in
[`scripts/validate/allowed-skips.txt`](../scripts/validate/README.md) — only
excuses the gap. Vendor when a CRD is obtainable; declare only when it is not.

<br/>

## Layout

```
schemas/<group>/<kind-lowercased>_<version>.json
```

This mirrors the datree catalog exactly, both in path shape and in content (the
CRD's `spec.versions[].schema.openAPIV3Schema`, verbatim). kubeconform lowercases
`{{.ResourceKind}}` when expanding a `-schema-location` template, so the filename
must be lowercase for the lookup to hit. A file here is a drop-in stand-in until
catalog coverage catches up, and can be contributed upstream as-is.

<br/>

## Contents

| Schema | Kind | Upstream source |
|---|---|---|
| `gateway.nginx.org/proxysettingspolicy_v1alpha1.json` | `ProxySettingsPolicy` (NGINX Gateway Fabric) | [`config/crd/bases/gateway.nginx.org_proxysettingspolicies.yaml`](https://github.com/nginx/nginx-gateway-fabric/blob/main/config/crd/bases/gateway.nginx.org_proxysettingspolicies.yaml) |

`ProxySettingsPolicy` is a current, valid NGF kind — the datree catalog carries
its siblings (`clientsettingspolicy`, `observabilitypolicy`,
`upstreamsettingspolicy`, `snippetsfilter`, `nginxproxy`) but not this one. It is
emitted by the `unity-mcp-server` chart.

<br/>

## Regenerating / adding a schema

Never hand-edit these files — regenerate them from the upstream CRD:

```bash
scripts/validate/vendor-crd-schema.sh <crd-url-or-path>
```

The script accepts a URL or a local path, handles multi-document YAML, and
writes one file per CRD version. After adding a schema, drop the kind's line
from `scripts/validate/allowed-skips.txt` if it had one, then confirm the kind
flips from skipped to valid:

```bash
make validate CHART=<chart>
```

<br/>

## Not chart content

This directory is maintainer tooling. It sits outside `charts/`, so it is never
packaged into a chart tarball and needs no `.helmignore` entry.
