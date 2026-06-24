# metallb-cr

Data-driven MetalLB **configuration** custom resources, deployed as a Helm release alongside the upstream MetalLB chart.

The upstream [`metallb/metallb`](https://github.com/metallb/metallb) chart installs the controller, speaker and CRDs but **does not template config CRs** (`IPAddressPool`, `L2Advertisement`, `BGPPeer`, ...) — those are left for you to apply out-of-band (typically `kubectl apply -f` in a post-install hook). This chart closes that gap so the MetalLB configuration is managed declaratively in Git, versioned, and rolled out with the same `helm` / `helmfile` flow as the operator.

<br/>

## What it deploys

| Resource | API | Created from |
|---|---|---|
| `IPAddressPool` | `metallb.io/v1beta1` | `ipAddressPools[]` |
| `L2Advertisement` | `metallb.io/v1beta1` | `l2Advertisements[]` |
| `BGPAdvertisement` | `metallb.io/v1beta1` | `bgpAdvertisements[]` |
| `BGPPeer` | `metallb.io/v1beta2` | `bgpPeers[]` |
| `Community` | `metallb.io/v1beta1` | `communities[]` |
| `BFDProfile` | `metallb.io/v1beta1` | `bfdProfiles[]` |

Every list defaults to empty, so an unconfigured `helm install` creates nothing.

<br/>

## Prerequisites

- Kubernetes >= 1.25
- MetalLB controller + speaker + CRDs already installed in the target namespace — typically via the upstream `metallb/metallb` chart. This chart only creates config CRs; it does not install MetalLB itself or its CRDs.

<br/>

## Install

OCI registry:

```bash
helm install metallb-config oci://ghcr.io/somaz94/charts/metallb-cr \
  --namespace metallb \
  -f my-values.yaml
```

Classic Helm repo:

```bash
helm repo add somaz94 https://charts.somaz.blog
helm install metallb-config somaz94/metallb-cr \
  --namespace metallb \
  -f my-values.yaml
```

<br/>

## Quick examples

### L2 mode (the common bare-metal case)

```yaml
ipAddressPools:
  - name: ip-pool
    addresses:
      - 192.0.2.10-192.0.2.50
    autoAssign: true

l2Advertisements:
  - name: l2-network
    ipAddressPools:
      - ip-pool
```

### L2 advertised only from worker nodes

```yaml
ipAddressPools:
  - name: ip-pool
    addresses:
      - 192.0.2.10-192.0.2.50

l2Advertisements:
  - name: l2-workers
    ipAddressPools:
      - ip-pool
    nodeSelectors:
      - matchLabels:
          node-role.kubernetes.io/worker: ""
```

### BGP mode with BFD

```yaml
ipAddressPools:
  - name: ip-pool
    addresses:
      - 192.0.2.0/24

bfdProfiles:
  - name: fast
    receiveInterval: 100
    transmitInterval: 100
    detectMultiplier: 3

bgpPeers:
  - name: tor-1
    myASN: 64512
    peerASN: 64512
    peerAddress: 203.0.113.254
    bfdProfile: fast

bgpAdvertisements:
  - name: bgp-default
    ipAddressPools:
      - ip-pool
    aggregationLength: 32
```

> BGP requires a BGP backend (`frrk8s.enabled` / `frr.enabled`) in the upstream MetalLB chart.

### Namespace-restricted pool

```yaml
ipAddressPools:
  - name: prod-only
    addresses:
      - 203.0.113.0/28
    autoAssign: false
    serviceAllocation:
      priority: 50
      namespaces:
        - prod
```

<br/>

## Values reference

### Metadata

| Key | Default | Description |
|---|---|---|
| `commonLabels` | `{}` | Labels added to every resource. |
| `commonAnnotations` | `{}` | Annotations added to every resource. |

### IPAddressPools — `ipAddressPools[]`

| Field | Required | Description |
|---|---|---|
| `name` | yes | Resource name. |
| `addresses` | yes | List of CIDRs or `start-end` ranges. |
| `autoAssign` | no | Auto-assign from this pool (upstream default `true`). |
| `avoidBuggyIPs` | no | Skip `.0` / `.255` (upstream default `false`). |
| `serviceAllocation` | no | Restrict the pool to namespaces / services (`priority`, `namespaces`, `namespaceSelectors`, `serviceSelectors`). |
| `labels` / `annotations` | no | Extra metadata on this resource. |
| `specExtra` | no | Arbitrary YAML merged into `spec` for unsurfaced fields. |

### L2Advertisements — `l2Advertisements[]`

| Field | Required | Description |
|---|---|---|
| `name` | yes | Resource name. |
| `ipAddressPools` | no | Pool names to advertise. |
| `ipAddressPoolSelectors` | no | Label selectors to pick pools. |
| `nodeSelectors` | no | Limit announcing nodes. |
| `interfaces` | no | Limit announcing interfaces. |
| `labels` / `annotations` / `specExtra` | no | — |

### BGPAdvertisements — `bgpAdvertisements[]`

| Field | Required | Description |
|---|---|---|
| `name` | yes | Resource name. |
| `aggregationLength` | no | IPv4 aggregation length (default `32`). |
| `aggregationLengthV6` | no | IPv6 aggregation length (default `128`). |
| `localPref` | no | BGP `LOCAL_PREF`. |
| `communities` | no | BGP communities to attach. |
| `ipAddressPools` | no | Pool names to advertise. |
| `ipAddressPoolSelectors` | no | Label selectors to pick pools. |
| `nodeSelectors` | no | Limit announcing nodes. |
| `peers` | no | Limit to specific `BGPPeer` names. |
| `labels` / `annotations` / `specExtra` | no | — |

### BGPPeers — `bgpPeers[]`

| Field | Required | Description |
|---|---|---|
| `name` | yes | Resource name. |
| `myASN` | yes | Local AS number. |
| `peerASN` | no | Remote AS number (mutually exclusive with `dynamicASN`). |
| `dynamicASN` | no | `internal` / `external` instead of a fixed `peerASN`. |
| `peerAddress` | no | Neighbor IP (mutually exclusive with `interface`). |
| `interface` | no | Interface for unnumbered BGP. |
| `peerPort` | no | Neighbor port (default `179`). |
| `holdTime` / `keepaliveTime` / `connectTime` | no | Session timers. |
| `routerID` / `sourceAddress` / `vrf` | no | — |
| `ebgpMultiHop` / `disableMP` / `enableGracefulRestart` | no | Boolean session options. |
| `bfdProfile` | no | `BFDProfile` name to associate. |
| `password` | no | Plaintext BGP MD5 password (prefer `passwordSecret`). |
| `passwordSecret` | no | `SecretReference` (`{ name, namespace }`) for the password. |
| `nodeSelectors` | no | Limit which nodes peer. |
| `labels` / `annotations` / `specExtra` | no | — |

### Communities — `communities[]`

| Field | Required | Description |
|---|---|---|
| `name` | yes | Resource name. |
| `communities` | yes | List of `{ name, value }` alias entries. |
| `labels` / `annotations` | no | — |

### BFDProfiles — `bfdProfiles[]`

| Field | Required | Description |
|---|---|---|
| `name` | yes | Resource name. |
| `receiveInterval` / `transmitInterval` / `detectMultiplier` / `echoInterval` | no | Timing parameters. |
| `echoMode` / `passiveMode` | no | Boolean modes. |
| `minimumTtl` | no | Minimum TTL for received packets. |
| `labels` / `annotations` | no | — |

<br/>

## License

[Apache-2.0](../../LICENSE)
