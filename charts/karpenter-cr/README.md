# karpenter-cr

Data-driven custom resources (`EC2NodeClass`, `NodePool`) for [AWS Karpenter](https://karpenter.sh/) — deployed alongside the upstream controller chart, or on their own against an EKS Auto Mode cluster.

The chart ships **no opinionated pools** — you describe any number of node classes and pools in values, and the templates render them. Add a pool by appending one entry; no template edits.

Both ways of running Karpenter on AWS are supported: the **self-managed** controller (you install it, it serves `EC2NodeClass`) and **EKS Auto Mode** (AWS runs Karpenter for you and serves its own `NodeClass`). See [Modes](#modes).

<br/>

## Modes

`NodePool` is `karpenter.sh/v1` in both modes — only the node class it binds to differs, so one `nodePools[]` list serves both.

| | Self-managed Karpenter | EKS Auto Mode |
|---|---|---|
| Node class API | `karpenter.k8s.aws/v1` `EC2NodeClass` | `eks.amazonaws.com/v1` `NodeClass` |
| Who creates the class | this chart, from `nodeClasses[]` | AWS — a built-in class named `default` |
| `nodeClassGroup` / `nodeClassKind` | `karpenter.k8s.aws` / `EC2NodeClass` (defaults) | `eks.amazonaws.com` / `NodeClass` |
| `nodeClasses[]` | one entry per launch profile | **leave empty** |
| Controller | you install it | built in |

Under Auto Mode the class is AWS-owned, so `nodeClasses[]` must stay empty — rendering an `EC2NodeClass` there applies a CRD the cluster does not serve. Point each pool at the built-in class with `nodeClassRef: default`.

<br/>

## What it deploys

| Resource | API | Created from |
|---|---|---|
| `EC2NodeClass` | `karpenter.k8s.aws/v1` | `nodeClasses[]` (self-managed only) |
| `NodePool` | `karpenter.sh/v1` | `nodePools[]` |

Both lists default to empty, so an unconfigured `helm install` creates nothing.

<br/>

## Prerequisites

Self-managed Karpenter:

- A Kubernetes cluster (EKS) with the Karpenter **controller** already installed (this chart only ships the CRs, not the controller).
- The Karpenter CRDs present (`ec2nodeclasses.karpenter.k8s.aws`, `nodepools.karpenter.sh`).
- Subnets and the node security group tagged for discovery (`<discoveryKey> = <clusterName>`), or per-entry explicit `subnetSelectorTerms` / `securityGroupSelectorTerms`.
- A Karpenter **node** IAM role name (provisioned out-of-band, e.g. by the `terraform-aws-eks` karpenter submodule).

EKS Auto Mode — none of the above apply. The controller, the CRDs, the node role and subnet discovery are all part of the cluster, so the only prerequisite is that Auto Mode is enabled (`computeConfig.enabled`).

<br/>

## Install

OCI registry:

```bash
helm install karpenter-cr oci://ghcr.io/somaz94/charts/karpenter-cr \
  --namespace karpenter \
  -f my-values.yaml
```

Classic Helm repo:

```bash
helm repo add somaz94 https://charts.somaz.blog
helm install karpenter-cr somaz94/karpenter-cr \
  --namespace karpenter \
  -f my-values.yaml
```

<br/>

## Quick examples

Minimal values:

```yaml
clusterName: my-cluster
nodeClassDefaults:
  role: KarpenterNodeRole-my-cluster   # IAM role NAME, not ARN
  amiAlias: al2023@latest              # required (or set amiSelectorTerms per entry)

nodeClasses:
  - name: build

nodePools:
  - name: build
    labels:
      nodegroup-workload: build
    taints:
      - key: dedicated
        value: build
        effect: NoSchedule
    requirements:
      - key: kubernetes.io/arch
        operator: In
        values: ["arm64"]
      - key: karpenter.sh/capacity-type
        operator: In
        values: ["spot"]
      - key: karpenter.k8s.aws/instance-family
        operator: In
        values: ["c7g", "c6g", "m7g", "m6g"]
      - key: karpenter.k8s.aws/instance-size
        operator: In
        values: ["xlarge"]
    limits:
      cpu: "24"
```

EKS Auto Mode — no `nodeClasses`, no `clusterName`, no IAM role:

```yaml
nodePoolDefaults:
  nodeClassGroup: eks.amazonaws.com
  nodeClassKind: NodeClass
  terminationGracePeriod: 24h

nodePools:
  - name: system
    nodeClassRef: default            # the class AWS ships
    labels:
      nodegroup-workload: system
    taints:
      - key: dedicated
        value: system
        effect: NoSchedule
    requirements:
      - key: karpenter.sh/capacity-type
        operator: In
        values: ["on-demand"]
      - key: eks.amazonaws.com/instance-category
        operator: In
        values: ["c", "m", "r"]
      - key: kubernetes.io/arch
        operator: In
        values: ["arm64"]
    disruption:
      consolidationPolicy: WhenEmpty   # keep the control plane still
```

Note the requirement keys: Auto Mode exposes `eks.amazonaws.com/instance-*`, not the `karpenter.k8s.aws/instance-*` keys the self-managed provider uses.

<br/>

## Values reference

| Key | Description | Default |
|-----|-------------|---------|
| `clusterName` | Cluster name; the value of the discovery tag used for subnet / SG selection. | `""` |
| `discoveryKey` | Discovery tag key. | `karpenter.sh/discovery` |
| `commonLabels` / `commonAnnotations` | Added to every rendered resource. | `{}` |
| `nodeClassDefaults` | Shared EC2NodeClass fields (`amiFamily`, `amiAlias`, `role`, `metadataOptions`, `blockDeviceMappings`, `tags`). | see `values.yaml` |
| `nodePoolDefaults` | Shared NodePool fields (`nodeClassGroup`, `nodeClassKind`, `terminationGracePeriod`, `disruption`, `limits`). | see `values.yaml` |
| `nodeClasses[]` | EC2NodeClasses to render. Inherits `nodeClassDefaults`; override inline. Empty under Auto Mode. | `[]` |
| `nodePools[]` | NodePools to render. Inherits `nodePoolDefaults`; references a class via `nodeClassRef`. | `[]` |

<br/>

### EC2NodeClass entry

`name` (required), `role`, `amiFamily`, `amiAlias`, `amiSelectorTerms`, `subnetSelectorTerms`, `securityGroupSelectorTerms`, `metadataOptions`, `blockDeviceMappings`, `tags`, `labels`, `annotations`, `kubelet`, `userData`, `detailedMonitoring`. AMI selection is **required** with no default (avoids silent AMI drift): set `amiAlias` or `amiSelectorTerms`. When `subnet` / `securityGroupSelectorTerms` are omitted they default to the discovery tag.

<br/>

### NodePool entry

`name` (required), `nodeClassRef` (default: `name`), `nodeClassGroup`, `nodeClassKind`, `labels`, `annotations`, `podAnnotations`, `taints`, `startupTaints`, `requirements` (required, raw Karpenter requirement list), `limits`, `disruption`, `terminationGracePeriod`, `weight`.

`nodeClassGroup` / `nodeClassKind` select which node class API the pool binds to and fall back to `nodePoolDefaults`; set them there once rather than per entry unless a single release spans both modes. See [Modes](#modes).

<br/>

## Notes

- Targets the Karpenter **v1** API (`karpenter.sh/v1` pools, `karpenter.k8s.aws/v1` classes); requires Karpenter `>= 1.0`. Under EKS Auto Mode the pool API is the same and the class is `eks.amazonaws.com/v1`.
- CRs are cluster-scoped; this chart does not create a namespace.

<br/>

## License

[Apache-2.0](../../LICENSE)
