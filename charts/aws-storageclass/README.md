# aws-storageclass

Data-driven AWS **StorageClasses** — EBS and EFS — rendered as a Helm release from a single list of per-entry-toggleable inputs.

EKS ships no default StorageClass, and the AWS EBS/EFS CSI drivers install the provisioners but do **not** create StorageClass objects — those are left for you to apply out-of-band. This chart closes that gap: declare any number of classes (`gp3`, `gp2`, `io2`, EFS, ...) in one list, toggle each with `enabled`, and manage them declaratively in Git with the same `helm` / `helmfile` flow as the rest of the platform.

<br/>

## What it deploys

| Resource | API | Created from |
|---|---|---|
| `StorageClass` | `storage.k8s.io/v1` | `storageClasses[]` (one per enabled entry) |

`storageClasses` defaults to empty, so an unconfigured `helm install` creates nothing. StorageClass is cluster-scoped — the release namespace is used only for Helm bookkeeping.

<br/>

## Prerequisites

- Kubernetes >= 1.25
- The matching AWS CSI driver installed for each provisioner you use:
  - EBS classes (`ebs.csi.aws.com`) → [aws-ebs-csi-driver](https://github.com/kubernetes-sigs/aws-ebs-csi-driver)
  - EFS classes (`efs.csi.aws.com`) → [aws-efs-csi-driver](https://github.com/kubernetes-sigs/aws-efs-csi-driver)

This chart only creates StorageClass objects; it does not install the CSI drivers.

<br/>

## Install

These snippets install the latest published chart. To pin an exact chart version, add `--version <x.y.z>` — released versions are the GitHub Release tags named `aws-storageclass-<version>`.

<br/>

### OCI registry (Helm 3.8+)

```bash
helm install storageclasses oci://ghcr.io/somaz94/charts/aws-storageclass \
  --namespace kube-system \
  -f my-values.yaml
```

<br/>

### Classic Helm repo

```bash
helm repo add somaz94 https://charts.somaz.blog
helm install storageclasses somaz94/aws-storageclass \
  --namespace kube-system \
  -f my-values.yaml
```

<br/>

## Quick examples

<br/>

### A single gp3 encrypted default class

```yaml
storageClasses:
  - name: ebs-sc
    provisioner: ebs.csi.aws.com
    isDefault: true
    volumeBindingMode: WaitForFirstConsumer
    reclaimPolicy: Retain
    allowVolumeExpansion: true
    parameters:
      type: gp3
      encrypted: "true"
```

<br/>

### Multiple EBS tiers + EFS, gp2 kept off

```yaml
storageClasses:
  - enabled: true
    name: ebs-sc               # gp3, default
    provisioner: ebs.csi.aws.com
    isDefault: true
    volumeBindingMode: WaitForFirstConsumer
    reclaimPolicy: Retain
    allowVolumeExpansion: true
    parameters:
      type: gp3
      encrypted: "true"

  - enabled: false             # defined but not rendered
    name: ebs-gp2
    provisioner: ebs.csi.aws.com
    volumeBindingMode: WaitForFirstConsumer
    reclaimPolicy: Delete
    allowVolumeExpansion: true
    parameters:
      type: gp2
      encrypted: "true"

  - enabled: true
    name: efs-sc
    provisioner: efs.csi.aws.com
    volumeBindingMode: Immediate
    reclaimPolicy: Retain
    mountOptions:
      - tls
    parameters:
      provisioningMode: efs-ap
      fileSystemId: fs-0123456789abcdef0
      directoryPerms: "700"
```

<br/>

### Zone-restricted io2 (allowedTopologies)

```yaml
storageClasses:
  - name: ebs-io2
    provisioner: ebs.csi.aws.com
    volumeBindingMode: WaitForFirstConsumer
    reclaimPolicy: Retain
    allowVolumeExpansion: true
    parameters:
      type: io2
      iops: "10000"
      encrypted: "true"
    allowedTopologies:
      - matchLabelExpressions:
          - key: topology.ebs.csi.aws.com/zone
            values:
              - eu-central-1a
```

<br/>

## Values reference

The tables below mirror [`values.yaml`](values.yaml), which is authoritative; [`values.schema.json`](values.schema.json) enforces the shape.

<br/>

### Top level

| Key | Type | Default | Description |
|---|---|---|---|
| `commonLabels` | map | `{}` | Labels added to every StorageClass. |
| `commonAnnotations` | map | `{}` | Annotations added to every StorageClass. |
| `storageClasses` | list | `[]` | StorageClass definitions (see below). Empty = no-op install. |

<br/>

### `storageClasses[]` entry

| Field | Type | Required | Description |
|---|---|---|---|
| `enabled` | bool | no (default `true`) | Render this class. Set `false` to keep the definition but skip it. |
| `name` | string | **yes** | StorageClass name. |
| `provisioner` | string | **yes** | CSI provisioner (`ebs.csi.aws.com` / `efs.csi.aws.com`). |
| `isDefault` | bool | no | Adds `storageclass.kubernetes.io/is-default-class: "true"`. Only one class per cluster should be default. |
| `parameters` | map | no | CSI parameters (string:string). EBS: `type`, `encrypted`, `iops`, `throughput`, `kmsKeyId`. EFS: `provisioningMode`, `fileSystemId`, `directoryPerms`. |
| `volumeBindingMode` | string | no | `Immediate` or `WaitForFirstConsumer`. |
| `reclaimPolicy` | string | no | `Retain` or `Delete`. |
| `allowVolumeExpansion` | bool | no | Allow online volume resize (EBS). |
| `mountOptions` | list | no | Mount options (common for EFS: `tls`). |
| `allowedTopologies` | list | no | Restrict provisioning to zones/topologies. |
| `labels` | map | no | Extra labels on this StorageClass. |
| `annotations` | map | no | Extra annotations on this StorageClass. |
| `parametersExtra` | map | no | Extra key/values merged into `parameters` for unsurfaced CSI fields. |

<br/>

## License

Apache-2.0. See [LICENSE](../../LICENSE).
