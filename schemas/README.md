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
| `gateway.nginx.org/clientsettingspolicy_v1alpha1.json` | `ClientSettingsPolicy` (NGINX Gateway Fabric) | [`config/crd/bases/gateway.nginx.org_clientsettingspolicies.yaml` @ v2.7.0](https://github.com/nginx/nginx-gateway-fabric/blob/v2.7.0/config/crd/bases/gateway.nginx.org_clientsettingspolicies.yaml) |
| `external-secrets.io/secretstore_v1.json` | `SecretStore` (External Secrets Operator) | [`config/crds/bases/external-secrets.io_secretstores.yaml` @ v2.12.0](https://github.com/external-secrets/external-secrets/blob/v2.12.0/config/crds/bases/external-secrets.io_secretstores.yaml) |
| `external-secrets.io/clustersecretstore_v1.json` | `ClusterSecretStore` (External Secrets Operator) | [`config/crds/bases/external-secrets.io_clustersecretstores.yaml` @ v2.12.0](https://github.com/external-secrets/external-secrets/blob/v2.12.0/config/crds/bases/external-secrets.io_clustersecretstores.yaml) |

There are three reasons to vendor, and the table above has an example of each.

`ProxySettingsPolicy` is ABSENT from the datree catalog, which carries its
siblings (`observabilitypolicy`, `upstreamsettingspolicy`, `snippetsfilter`,
`nginxproxy`) but not this one.

The `ClientSettingsPolicy` link is pinned to a tag, not `main`, because the two
must stay reproducible together: re-running `vendor-crd-schema.sh` against the
link has to reproduce the file byte for byte. A `main` link stops doing that the
moment upstream merges the next field.

Re-pin it whenever the chart starts offering a field a newer NGF added: the
fields `charts/nginx-gateway-cr/values.schema.json` accepts and the fields this
vendored schema declares have to come from the same upstream release, so there is
never a second question about which one is authoritative. `values.schema.json` is
JSON and cannot record the tag itself — the table above is where that tag lives.
The per-field minimum NGF version belongs in that chart's README values table,
not here: this file records where the schema came from, not who can use it.

Only the tag-pinned rows need this. `ProxySettingsPolicy` is vendored because the
catalog has NO entry for it, so nothing is being overridden and the file has no
field set to keep aligned with a chart — a `main` link is fine there.

`ClientSettingsPolicy` IS in the catalog, but STALE: the catalog entry predates
`spec.keepAlive.minTimeout` (NGF v2.6.0) and `spec.body.bufferSize` (v2.7.0), and
sets
`additionalProperties: false`, so kubeconform's `-strict` rejects a valid policy
that sets it. This is the failure mode the second paragraph of "Why this exists"
describes — a published entry that is wrong rather than missing — and it fails
loudly (`invalid`), not as a silent skip.

`SecretStore` and `ClusterSecretStore` ARE in the catalog, but MALFORMED since
its 2026-10-08 refresh to ESO v2.12.0. ESO's `crd` provider has a field literally
named `properties` (`whitelist.rules[].properties`), and the catalog's converter
injected `"additionalProperties": false` into that field map as if it were a
property. kubeconform cannot compile the result, moves on to the next location,
and reports the kind as having no schema — so the gate fails with an undeclared
skip while the file sits right there. Only the `v1` files are kept; the chart
renders no `v1beta1`. Drop both once the catalog entry compiles again:
`make validate CHART=external-secrets-cr` with them moved aside and an empty
`KUBECONFORM_CACHE` is the check.

Before re-pinning either schema, list its emitters — every chart that renders the
kind validates against this one file, so a re-pin driven by a single chart can
silently break a sibling:

```bash
grep -rl 'kind: ClientSettingsPolicy' charts/*/templates/
```

One consequence worth knowing: upstream CRDs do not set `additionalProperties`,
and neither does a file vendored from one. The datree entry it replaces did. So
for a vendored kind, kubeconform stops rejecting unknown keys — validation of
misspelled fields falls entirely to the chart's own `values.schema.json`.

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
