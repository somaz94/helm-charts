# scripts/validate

<br/>

Guards for `make validate` — the kubeconform pass that checks every chart's
rendered output against Kubernetes and CRD schemas.

<br/>

## Purpose

`make validate` runs kubeconform with `-ignore-missing-schemas`. That flag is
necessary: this collection's `-cr` charts emit custom resources, and a CRD whose
schema no public catalog has published yet would otherwise break the entire run.

The flag has a cost. A resource whose schema cannot be resolved is reported
`statusSkipped` and kubeconform **still exits 0**. The chart ships that resource
unvalidated while CI stays green — and nothing in the output distinguishes
"validated 8 resources" from "validated 7 and quietly ignored 1".

That blind spot is unbounded: every future CR kind missing from the upstream
catalog joins it invisibly. This directory closes it two ways.

| Path | File | Effect |
|---|---|---|
| Fix the gap | `vendor-crd-schema.sh` | Convert the upstream CRD into a repo-local schema so the resource is actually validated. |
| Declare the gap | `allowed-skips.txt` | Record a kind that has no obtainable schema, with a written reason. |
| Enforce | `check-skips.sh` | Fail the run on any skip that is neither fixed nor declared. |

Prefer vendoring. A vendored schema validates the resource; a declaration only
excuses it.

<br/>

## Usage

```bash
# Normal run — the gate is wired into the Makefile, nothing extra to invoke.
make validate
make validate CHART=unity-mcp-server

# A new CR kind started reporting as an undeclared skip. Vendor its schema:
scripts/validate/vendor-crd-schema.sh \
  https://raw.githubusercontent.com/nginx/nginx-gateway-fabric/main/config/crd/bases/gateway.nginx.org_proxysettingspolicies.yaml

# Re-run; the kind should now validate instead of skip.
make validate CHART=unity-mcp-server
```

<br/>

## How it works

`make validate` renders each chart (plus its `ci/*.yaml` fixtures), pipes the
manifests through kubeconform with `-output json -verbose`, and pipes that
payload into `check-skips.sh`:

```
helm template → kubeconform -output json -verbose → check-skips.sh <chart>
```

`-verbose` matters — without it kubeconform omits passing and skipped resources
from the JSON, and the gate would have nothing to inspect.

`check-skips.sh` prints the per-chart summary that `-summary` used to print,
then exits 1 if any resource is invalid, or skipped without a matching line in
`allowed-skips.txt`. Undeclared skips are grouped by `(kind, apiVersion)` so one
unschema'd kind rendered N times is reported once with a tally.

<br/>

## Schema resolution order

`make validate` passes three `-schema-location` flags, consulted in order:

1. `default` — kubeconform's built-in store (`yannh/kubernetes-json-schema`) for
   core and built-in API groups.
2. `schemas/<group>/<kind>_<version>.json` — this repo's vendored CR schemas.
   Local wins over remote, so a vendored schema also lets you pin a kind whose
   catalog entry is wrong or lagging.
3. The datree `CRDs-catalog` over HTTPS — broad CR coverage, but it lags
   upstream releases.

Downloads are cached under `.kubeconform-cache/` (gitignored, cleared by
`make clean`). Without the cache an offline or rate-limited run would resolve
nothing and — with `-ignore-missing-schemas` — degrade to "everything skipped,
all green", the maximal form of the very blind spot this directory exists to
prevent.

<br/>

## `allowed-skips.txt` format

```
<chart>  <apiVersion>  <Kind>
```

`<chart>` is a chart directory name, or `*` for every chart. Blank lines and
`#` comments are ignored. Every entry carries a `# why:` note — an undocumented
allowance is indistinguishable from an oversight.

Currently one kind is declared: `CustomResourceDefinition`. kubeconform's
default store publishes no schema for it, and there is no CRD-of-a-CRD to
vendor, so `keycloak-operator`'s in-tree `templates/crd-*.yaml` (copied verbatim
from upstream) cannot be checked here.

<br/>

## Requirements

- `kubeconform` — `brew install kubeconform`
- `python3` — used by `check-skips.sh` to parse kubeconform JSON (stdlib only)
- `PyYAML` — **only** for `vendor-crd-schema.sh`, which is a maintainer action
  that never runs in CI. `pip install pyyaml`

`check-skips.sh` reads JSON on stdin and touches no network, so the CI path has
no dependency beyond `python3` itself.
