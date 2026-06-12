# karpenter-cr

Data-driven custom resources (`EC2NodeClass`, `NodePool`) for [AWS Karpenter](https://karpenter.sh/), deployed alongside the upstream Karpenter controller chart.

The chart ships **no opinionated pools** — you describe any number of node classes and pools in values, and the templates render them. Add a pool by appending one entry; no template edits.

<br/>

## Prerequisites

- A Kubernetes cluster (EKS) with the Karpenter **controller** already installed (this chart only ships the CRs, not the controller).
- The Karpenter CRDs present (`ec2nodeclasses.karpenter.k8s.aws`, `nodepools.karpenter.sh`).
- Subnets and the node security group tagged for discovery (`<discoveryKey> = <clusterName>`), or per-entry explicit `subnetSelectorTerms` / `securityGroupSelectorTerms`.
- A Karpenter **node** IAM role name (provisioned out-of-band, e.g. by the `terraform-aws-eks` karpenter submodule).

<br/>

## Usage

```bash
helm install karpenter-cr oci://<registry>/karpenter-cr -f my-values.yaml
```

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

<br/>

## Values

| Key | Description | Default |
|-----|-------------|---------|
| `clusterName` | Cluster name; the value of the discovery tag used for subnet / SG selection. | `""` |
| `discoveryKey` | Discovery tag key. | `karpenter.sh/discovery` |
| `commonLabels` / `commonAnnotations` | Added to every rendered resource. | `{}` |
| `nodeClassDefaults` | Shared EC2NodeClass fields (`amiFamily`, `amiAlias`, `role`, `metadataOptions`, `blockDeviceMappings`, `tags`). | see `values.yaml` |
| `nodePoolDefaults` | Shared NodePool fields (`disruption`, `limits`). | see `values.yaml` |
| `nodeClasses[]` | EC2NodeClasses to render. Inherits `nodeClassDefaults`; override inline. | `[]` |
| `nodePools[]` | NodePools to render. Inherits `nodePoolDefaults`; references a class via `nodeClassRef`. | `[]` |

<br/>

### EC2NodeClass entry

`name` (required), `role`, `amiFamily`, `amiAlias`, `amiSelectorTerms`, `subnetSelectorTerms`, `securityGroupSelectorTerms`, `metadataOptions`, `blockDeviceMappings`, `tags`, `labels`, `annotations`, `kubelet`, `userData`, `detailedMonitoring`. AMI selection is **required** with no default (avoids silent AMI drift): set `amiAlias` or `amiSelectorTerms`. When `subnet` / `securityGroupSelectorTerms` are omitted they default to the discovery tag.

<br/>

### NodePool entry

`name` (required), `nodeClassRef` (default: `name`), `labels`, `annotations`, `podAnnotations`, `taints`, `startupTaints`, `requirements` (required, raw Karpenter requirement list), `limits`, `disruption`, `weight`.

<br/>

## Notes

- Targets the Karpenter **v1** API (`karpenter.k8s.aws/v1`, `karpenter.sh/v1`); requires Karpenter `>= 1.0`.
- CRs are cluster-scoped; this chart does not create a namespace.
