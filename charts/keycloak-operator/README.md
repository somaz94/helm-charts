# keycloak-operator

A Helm chart that wraps the upstream [Keycloak Operator](https://www.keycloak.org/operator/installation) raw YAML — published by the Keycloak project at [`keycloak/keycloak-k8s-resources`](https://github.com/keycloak/keycloak-k8s-resources) under `kubernetes/`.

The Keycloak project does **not** ship a Helm chart for the operator (only the raw `kubernetes.yml` and the two CRDs). This chart packages those manifests, makes the namespace, image, watch-scope and resource limits configurable, and ships an `upgrade.sh` that tracks new keycloak-k8s-resources tags and refreshes the in-tree CRD templates.

After installing this chart, use the [`keycloak-cr`](../keycloak-cr) chart to render Keycloak instances (`Keycloak`, `KeycloakRealmImport` CRs).

<br/>

## What it deploys

| Resource | API | Purpose |
|---|---|---|
| `CustomResourceDefinition` (Keycloak) | `apiextensions.k8s.io/v1` | Defines `k8s.keycloak.org/v2beta1` `Keycloak` CR. |
| `CustomResourceDefinition` (KeycloakRealmImport) | `apiextensions.k8s.io/v1` | Defines `k8s.keycloak.org/v2beta1` `KeycloakRealmImport` CR. |
| `ServiceAccount` (`keycloak-operator`) | `v1` | Operator identity. |
| `ClusterRole` (×3) | `rbac.authorization.k8s.io/v1` | OpenShift `ingresses` read; `keycloaks` controller; `keycloakrealmimports` controller. |
| `ClusterRoleBinding` | `rbac.authorization.k8s.io/v1` | Binds the operator SA to the OpenShift-ingresses read role cluster-wide. |
| `Role` + `RoleBinding` (×4) | `rbac.authorization.k8s.io/v1` | Namespace-scoped permissions for managing `StatefulSet`, `Service`, `Secret`, `Job`, `Ingress`, `ServiceMonitor` plus `view` access. |
| `Service` (`keycloak-operator`) | `v1` | Health/metrics endpoint on port 80 → 8080. |
| `Deployment` (`keycloak-operator`) | `apps/v1` | One operator pod with liveness/readiness/startup probes against `/q/health/*`. |

<br/>

## Versioning

| Field | Meaning |
|---|---|
| `Chart.yaml` `version` | The chart's own SemVer. Bumped manually via `make bump CHART=keycloak-operator LEVEL=patch\|minor\|major` for template/schema changes. |
| `Chart.yaml` `appVersion` | The pinned Keycloak Operator release (and Keycloak server image tag). Tracked by `upgrade.sh` against [`keycloak/keycloak-k8s-resources`](https://github.com/keycloak/keycloak-k8s-resources/tags). |
| `values.yaml` `version` | Identical to `appVersion` by default. Used to render the operator image tag and the `RELATED_IMAGE_KEYCLOAK` env value when `image.tag` / `serverImage.tag` are left empty. |

<br/>

## Prerequisites

- Kubernetes **1.25+**
- Permission to create cluster-scoped resources (CRDs, `ClusterRole`, `ClusterRoleBinding`).
- For `serviceMonitor` reconciliation by the operator, the [Prometheus Operator](https://github.com/prometheus-operator/prometheus-operator) installed (Keycloak CRs can opt into ServiceMonitor creation).

<br/>

## Install

<br/>

### OCI registry (Helm 3.8+)

```bash
helm install keycloak-operator oci://ghcr.io/somaz94/charts/keycloak-operator \
  --version 0.1.0 \
  --namespace keycloak-system --create-namespace
```

<br/>

### Classic Helm repo

```bash
helm repo add somaz94 https://charts.somaz.blog
helm repo update
helm install keycloak-operator somaz94/keycloak-operator \
  --namespace keycloak-system --create-namespace
```

<br/>

## Quick examples

<br/>

### 1. Default install (watch own namespace)

```bash
helm install keycloak-operator oci://ghcr.io/somaz94/charts/keycloak-operator \
  -n keycloak-system --create-namespace
```

The operator only reconciles `Keycloak` / `KeycloakRealmImport` CRs in the `keycloak-system` namespace. Subsequently, install the `keycloak-cr` chart in `keycloak-system` (or set `watchNamespaces` below to a different scope).

<br/>

### 2. Watch every namespace cluster-wide

```yaml
watchNamespaces: JOSDK_WATCH_ALL
```

```bash
helm install keycloak-operator oci://ghcr.io/somaz94/charts/keycloak-operator \
  -n keycloak-system --create-namespace -f values.yaml
```

<br/>

### 3. Watch a specific list of namespaces

```yaml
watchNamespaces: "tenant-a,tenant-b"
```

<br/>

### 4. Air-gapped / private registry (override images)

```yaml
image:
  repository: registry.internal.example.com/keycloak/keycloak-operator
  tag: 26.6.1                            # operator image (defaults to .Values.version)
  pullPolicy: IfNotPresent

serverImage:
  repository: registry.internal.example.com/keycloak/keycloak
  tag: 26.6.1                            # rendered into RELATED_IMAGE_KEYCLOAK env

imagePullSecrets:
  - name: registry-internal-pull
```

<br/>

### 5. CRDs managed externally (chart only installs operator)

```yaml
crds:
  install: false                         # CRDs registered out-of-band (e.g. fleet GitOps)
```

When this flag is off, the chart skips both CRDs — the operator still references them, so `keycloaks.k8s.keycloak.org` and `keycloakrealmimports.k8s.keycloak.org` must be present in the cluster before this chart is applied.

<br/>

## Values reference

### Top-level

| Key | Type | Default | Description |
|---|---|---|---|
| `version` | string | matches `appVersion` | Pinned upstream version. Drives the default image tag and `RELATED_IMAGE_KEYCLOAK`. Rewritten by `upgrade.sh`. |
| `commonLabels` | object | `{}` | Labels added to every resource. |
| `commonAnnotations` | object | `{}` | Annotations added to every resource. |
| `resourceMetadata.<resource>.{labels,annotations}` | object | `{}` | Per-resource overrides. Resources: `serviceAccount`, `deployment`, `service`, `role`, `clusterRoles`, `roleBinding`, `clusterRoleBindings`. |

### Image

| Key | Type | Default | Description |
|---|---|---|---|
| `image.repository` | string | `quay.io/keycloak/keycloak-operator` | Operator image repository. |
| `image.tag` | string | `""` | Image tag. Empty → uses `.Values.version`. |
| `image.pullPolicy` | string | `IfNotPresent` | `Always`, `IfNotPresent`, or `Never`. |
| `serverImage.repository` | string | `quay.io/keycloak/keycloak` | Keycloak server image repository (`RELATED_IMAGE_KEYCLOAK`). |
| `serverImage.tag` | string | `""` | Empty → uses `.Values.version`. |
| `imagePullSecrets[]` | list | `[]` | Pull secrets attached to the operator Pods. |

### Deployment

| Key | Type | Default | Description |
|---|---|---|---|
| `replicas` | int | `1` | Operator replicas. The operator does not support active-active — keep at 1 unless using leader election. |
| `resources` | object | `{cpu: 300m–700m, mem: 450Mi}` | Compute resources. Defaults match upstream 26.6.1. |
| `nodeSelector`, `tolerations`, `affinity`, `priorityClassName`, `topologySpreadConstraints` | — | — | Standard pod-scheduling fields. |
| `podLabels`, `podAnnotations`, `podSecurityContext`, `securityContext` | object | `{}` | Pod template metadata + security contexts. |
| `extraEnv[]` | list | `[]` | Additional env vars (chart already wires `KUBERNETES_NAMESPACE`, `RELATED_IMAGE_KEYCLOAK`, watch-scope vars). |
| `watchNamespaces` | string | `JOSDK_WATCH_CURRENT` | `JOSDK_WATCH_CURRENT` (own NS), `JOSDK_WATCH_ALL` (cluster-wide), or `ns-a,ns-b` list. |
| `probes.{liveness,readiness,startup}` | object | upstream defaults | Probe knobs. |
| `volumes`, `volumeMounts` | list | `[]` | Operator container volumes. |
| `deploymentExtra` | object | `{}` | **Escape hatch.** Merged into `Deployment.spec`. |
| `containerExtra` | object | `{}` | **Escape hatch.** Merged into the operator container spec. |

### Service / ServiceAccount / RBAC / CRDs

| Key | Type | Default | Description |
|---|---|---|---|
| `service.enabled` | bool | `true` | Render the operator Service (health/metrics on port 80 → 8080). |
| `service.type`, `.port`, `.targetPort`, `.name`, `.annotations`, `.labels` | — | — | Standard Service knobs. |
| `serviceAccount.create` | bool | `true` | Render the SA. Disable to wire an externally-managed SA. |
| `serviceAccount.name` | string | `keycloak-operator` | SA name. The Deployment references this. |
| `rbac.create` | bool | `true` | Render `ClusterRole` / `ClusterRoleBinding` / `Role` / `RoleBinding`. |
| `rbac.subjectNamespace` | string | `""` (= `Release.Namespace`) | Namespace used as the `ClusterRoleBinding` subject's namespace. Override only when SA lives in a different namespace from the chart release. |
| `crds.install` | bool | `true` | Render the two CRDs in `templates/`. Disable when CRDs are managed externally. |
| `crds.keep` | bool | `true` | Add `helm.sh/resource-policy: keep` so the CRDs survive a chart uninstall. Recommended in production. |

<br/>

## Maintaining this chart

This chart wraps third-party YAML — both CRDs and the operator manifest evolve on the Keycloak release cadence. The chart-local `upgrade.sh` automates the bump:

```bash
cd charts/keycloak-operator
./upgrade.sh --dry-run                     # preview the next bump
./upgrade.sh                               # bump to the latest GA tag
./upgrade.sh --version 26.6.1              # pin to a specific tag
./upgrade.sh --rollback                    # restore from backup/<timestamp>/
./upgrade.sh --list-backups
./upgrade.sh --cleanup-backups             # keep last 5 (override KEEP_BACKUPS=N)
```

What it does on a successful bump:

1. Verifies `quay.io/keycloak/keycloak-operator:<version>` exists.
2. Backs up `Chart.yaml`, `values.yaml`, and the two CRD templates to `backup/<timestamp>/`.
3. Re-fetches `keycloaks.k8s.keycloak.org-v1.yml` and `keycloakrealmimports.k8s.keycloak.org-v1.yml` from the upstream tag, re-injects the chart's `{{- if .Values.crds.install }}` gate and labels/annotations block.
4. Rewrites `Chart.yaml` `appVersion` and `values.yaml` `version`.
5. Appends a `kind: changed` entry to `artifacthub.io/changes`.

What it does **not** do:
- Touch the cluster (no `kubectl`, `helm`, `helmfile`).
- Bump the chart's own SemVer (`Chart.yaml` `version`) — run `make bump CHART=keycloak-operator LEVEL=patch` after reviewing the diff.
- Refresh `templates/deployment.yaml` / `rbac.yaml` / `service.yaml` — those are chart-managed re-implementations of `kubernetes.yml`. Review the upstream `kubernetes.yml` diff manually after a major bump and update the chart templates if upstream changes (e.g. new env var, new RBAC verb).

<br/>

## License

[Apache-2.0](../../LICENSE)
