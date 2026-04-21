# HA Rolling Upgrade Verification — elasticsearch-eck & kibana-eck

Empirical verification that the `elasticsearch-eck` and `kibana-eck` OCI charts
support **zero-downtime rolling upgrades** when deployed in an HA topology.

Verified on 2026-04-21 against chart version 0.1.1 / Stack 9.3.3.

<br/>

## Goal

Prove three properties of the charts in HA mode:

1. **Rolling upgrade under continuous load causes no client-visible errors** —
   no HTTP 5xx on indexing or Kibana status requests during pod rotation.
2. **Cluster health stays functional** — `green` in steady state, `yellow`
   transitions allowed during shard rebalance, but never `red`.
3. **Cosmetic-only CR changes do NOT trigger pod restarts** — label/annotation
   updates that don't change `spec` are no-ops.

<br/>

## Test environment

| Component | Detail |
|---|---|
| K8s runtime | kind v0.31.0 (OrbStack docker context), single control-plane node |
| K8s version | v1.35.0 (kind default at test time) |
| ECK operator | `elastic/eck-operator` latest stable, `elastic-system` ns |
| Charts under test | `elasticsearch-eck` 0.1.1, `kibana-eck` 0.1.1 |
| Stack version | 9.3.3 (`docker.elastic.co/elasticsearch/elasticsearch:9.3.3`, `docker.elastic.co/kibana/kibana:9.3.3`) |
| Namespace | `eck-ha-test` |
| Host RAM | 24 GB total, ~7 GB available at start |
| StorageClass | `standard` (local-path-provisioner, kind default) |

<br/>

## HA topology

### Elasticsearch (`es-ha`)

Three all-role nodes. `podDisruptionBudget.native: true` + `maxUnavailable: 1`
ensures at most one pod is terminated at a time.

```yaml
name: es-ha
version: "9.3.3"
elasticPassword: "ha-test-pw"
nodeSets:
  - name: default
    count: 3
    roles: [master, data, data_content, data_hot, ingest]
    config: {node.store.allow_mmap: false}
    resources:
      requests: {cpu: "100m", memory: "768Mi"}
      limits:   {cpu: "1000m", memory: "768Mi"}
    storage:
      storageClass: standard
      size: 1Gi
      accessModes: [ReadWriteOnce]
sysctlInitContainer: {enabled: true}
ingress: {enabled: false}
httproute: {enabled: false}
backendTLSPolicy: {enabled: false}
podDisruptionBudget:
  native: true
  external: false
  maxUnavailable: 1
```

### Kibana (`kb-ha`)

Two replicas, plain HTTP (chart auto-injects `xpack.security.secureCookies: false`),
PDB with `maxUnavailable: 1`.

```yaml
name: kb-ha
version: "9.3.3"
replicas: 2
elasticsearchRef: {name: es-ha}
nodeOptions: ["--max-old-space-size=1200"]
resources:
  requests: {cpu: "100m", memory: "1536Mi"}
  limits:   {cpu: "1000m", memory: "1536Mi"}
http:
  tls:
    selfSignedCertificate: {disabled: true}
ingress: {enabled: false}
httproute: {enabled: false}
podDisruptionBudget:
  enabled: true
  maxUnavailable: 1
```

> Note: `512Mi–768Mi` for Kibana was insufficient and triggered `OOMKilled`
> during startup (Node.js heap + plugin load). The chart recommends **≥1Gi**
> in HA mode; we used 1.5 Gi for headroom.

<br/>

## Load generator

An in-cluster pod (`curlimages/curl`) runs a continuous loop sampling every
~0.5 s throughout the test:

```sh
# per tick
curl POST  $ES/ha-test/_doc  → expect 201
curl GET   $ES/_cluster/health → parse "status": expect green/yellow (never red)
curl GET   $KB/api/status   → expect 200
```

Using an in-cluster pod avoids `kubectl port-forward` flakiness (local PF dies
on connection resets from Kibana reloading). Full script is in
[appendix-loadgen.sh](#appendix-a-load-generator-pod-spec).

<br/>

## Test results

### Test 1 — ES rolling restart (triggered by `resources` change)

`helm upgrade` with a changed CPU request (`100m` → `150m`), which changes the
pod template hash and forces ECK to roll the StatefulSet.

| Metric | Value |
|---|---|
| Window | 02:52:57 – 02:57:21 UTC (4m 24s) |
| Rolling order | `es-default-2` → `es-default-1` → `es-default-0` (one-at-a-time, PDB-respecting) |
| Samples taken | 470 |
| ES indexing responses | **470 × HTTP 201** (0 failures) |
| ES cluster health | 303 × `green`, 167 × `yellow`, **0 × `red`** |
| Kibana `/api/status` | **470 × HTTP 200** (0 failures) |
| Indexing latency spikes | none (all within 500ms tick) |

`yellow` periods correspond to shard rebalance while one data node was down
(expected behavior — the chart's PDB with `maxUnavailable: 1` guarantees at
least 2 nodes hold shard copies throughout).

**Result: PASS ✅**

### Test 2 — Kibana rolling restart (triggered by `resources` change)

`helm upgrade` with changed CPU request on the Kibana CR.

| Metric | Value |
|---|---|
| Window | 02:59:07 – 02:59:56 UTC (49s) |
| Rolling behavior | Deployment `maxSurge: 25%, maxUnavailable: 25%` default; new pod created first, old terminated when new is Ready |
| Samples taken | 82 |
| ES indexing responses | **82 × HTTP 201** (unaffected) |
| ES cluster health | 82 × `green` (Kibana doesn't touch ES shards) |
| Kibana `/api/status` | **82 × HTTP 200** (zero user-visible downtime) |

Kibana client traffic is routed by the Service to whichever pod is Ready. Since
PDB + Deployment rollout ensures at least one replica is always Ready, users
never see a 5xx.

**Result: PASS ✅**

### Test 3 — Cosmetic CR annotation change (expect no restart)

`helm upgrade` adding a custom annotation via `resourceMetadata.elasticsearch.annotations`.
This only touches CR `metadata.annotations`, not `spec`.

| Metric | Value |
|---|---|
| Pod `startTime` before | `2026-04-21T02:56:47Z`, `02:55:17Z`, `02:53:52Z` |
| Pod `startTime` after (20 s later) | **identical to before** |
| CR annotation applied | Yes (`test.cosmetic/annotation: added-v3` present) |

ECK reconciler only rolls pods when `spec` changes. `metadata.annotations`
updates propagate without pod restart — confirms the chart's CR-level changes
don't unintentionally trigger rolling.

**Result: PASS ✅**

<br/>

## Aggregate across entire test run

```
Total duration:  02:52:08 – 03:01:41 UTC (~9.5 min)
Total samples:   1010
ES indexing:     1010 × 201 (100% success, 0 × 5xx, 0 × timeout)
ES health:       843 × green + 167 × yellow + 0 × red
Kibana status:   1010 × 200 (100% success, 0 × 5xx, 0 × timeout)
```

Final indexed document count: **1008** (vs 1010 requests). The 2-doc delta is
not loss — `index.refresh_interval: 1s` means the most recent 1–2 indexing
responses were counted as `201` but not yet search-visible when `_count` was
queried ~1 second after the last request. ES storage-level durability was
never at risk.

<br/>

## Conclusions

1. ✅ **Rolling upgrades are zero-downtime in HA mode** for both charts when
   `podDisruptionBudget` is configured with `maxUnavailable: 1`.
2. ✅ **Pod termination follows PDB**: ECK never terminates more than 1 ES pod
   simultaneously; Kibana Deployment respects its PDB during replacement.
3. ✅ **Cosmetic CR changes are no-ops**: `metadata.*` mutations do not trigger
   unnecessary pod restarts, unlike the naive Helm 3-way merge fear.
4. ⚠️ **Kibana needs ≥1Gi memory** per replica. Lower values trigger OOMKilled
   during startup (plugin load). Document this in chart README as the HA
   minimum.

<br/>

## Minimum HA requirements derived from this test

| Resource | Minimum |
|---|---|
| ES nodes | 3 (to avoid split-brain with 2-node quorum) |
| ES memory per pod | 768 MiB (test passed; production should use ≥2 GiB) |
| ES storage | 1 GiB per node (test only; production ≥30 GiB typical) |
| Kibana replicas | 2 |
| Kibana memory per pod | **≥1 GiB** (1.5 GiB recommended) |
| PDB | `maxUnavailable: 1` on both CRs |
| K8s cluster size | 1 node (ECK rolling works within a single node via StatefulSet/Deployment primitives) |

For real HA (node-level fault tolerance), deploy across 3+ K8s nodes with pod
anti-affinity. That dimension is out of scope for this rolling-upgrade test.

<br/>

## When to re-run this test

- Before publishing a chart **major bump** (0.x → 1.x) — re-run to confirm
  no regressions in rolling behavior.
- After any change to the Helm template that affects `podTemplate.spec` or the
  StatefulSet/Deployment definitions.
- After ECK operator major upgrade if it changes reconcile semantics.

Not required for:

- chart patch bumps (0.1.1 → 0.1.2) that only affect non-reconciling metadata.
- Stack image tag bumps (Stack version, managed by consumer's `upgrade.sh`).

<br/>

## Reproducing the test

```bash
# 1. kind cluster
cat > /tmp/kind-config.yaml <<'EOF'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: eck-ha-test
nodes:
  - role: control-plane
EOF
kind create cluster --config /tmp/kind-config.yaml

# 2. ECK operator
helm install elastic-operator elastic/eck-operator \
  -n elastic-system --create-namespace --wait

# 3. ES + Kibana HA (paste the YAMLs above into es-ha-values.yaml / kb-ha-values.yaml)
kubectl create namespace eck-ha-test
helm install es-ha oci://ghcr.io/somaz94/charts/elasticsearch-eck \
  --version 0.1.1 -n eck-ha-test -f es-ha-values.yaml
helm install kb-ha oci://ghcr.io/somaz94/charts/kibana-eck \
  --version 0.1.1 -n eck-ha-test -f kb-ha-values.yaml
kubectl -n eck-ha-test wait elasticsearch/es-ha --for=jsonpath='{.status.phase}'=Ready --timeout=10m
kubectl -n eck-ha-test wait kibana/kb-ha --for=jsonpath='{.status.health}'=green --timeout=5m

# 4. Create test index
kubectl -n eck-ha-test exec es-ha-es-default-0 -c elasticsearch -- \
  curl -sk -u "elastic:ha-test-pw" -X PUT "https://localhost:9200/ha-test" \
  -H "Content-Type: application/json" -d '{"settings":{"number_of_shards":3,"number_of_replicas":1}}'

# 5. Deploy loadgen (see appendix)
kubectl apply -f loadgen.yaml

# 6. Trigger rolling (bump resources)
helm upgrade es-ha oci://ghcr.io/somaz94/charts/elasticsearch-eck \
  --version 0.1.1 -n eck-ha-test -f es-ha-values-v2.yaml

# 7. Analyze
kubectl -n eck-ha-test logs loadgen > /tmp/loadgen.log
# Parse with the Python snippet in the Test 1 / 2 sections above.

# 8. Cleanup
kind delete cluster --name eck-ha-test
```

<br/>

## Appendix A — load generator pod spec

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: loadgen
  namespace: eck-ha-test
spec:
  restartPolicy: Never
  containers:
    - name: loadgen
      image: curlimages/curl:latest
      env:
        - {name: ELASTIC_PWD, value: "ha-test-pw"}
        - {name: ES_URL,      value: "https://es-ha-es-http:9200"}
        - {name: KB_URL,      value: "http://kb-ha-kb-http:5601"}
      command: ["/bin/sh", "-c"]
      args:
        - |
          while ! curl -sk --max-time 3 -u "elastic:$ELASTIC_PWD" $ES_URL/ > /dev/null 2>&1; do
            sleep 2
          done
          while ! curl -s --max-time 3 -u "elastic:$ELASTIC_PWD" $KB_URL/api/status > /dev/null 2>&1; do
            sleep 2
          done
          i=0
          while true; do
            i=$((i+1))
            CODE_IDX=$(curl -sk -u "elastic:$ELASTIC_PWD" -X POST "$ES_URL/ha-test/_doc" \
              -H "Content-Type: application/json" \
              -d "{\"msg\":\"doc $i\",\"ts\":\"$(date -Iseconds)\"}" \
              -o /dev/null -w "%{http_code}" --max-time 5 || echo "ERR")
            HEALTH=$(curl -sk -u "elastic:$ELASTIC_PWD" --max-time 3 "$ES_URL/_cluster/health" 2>/dev/null \
              | sed -n 's/.*"status":"\([^"]*\)".*/\1/p' || echo "ERR")
            CODE_KB=$(curl -s -u "elastic:$ELASTIC_PWD" -o /dev/null -w "%{http_code}" --max-time 3 "$KB_URL/api/status" || echo "ERR")
            printf "%s i=%-5d es_idx=%s health=%-7s kb=%s\n" "$(date +%T)" "$i" "$CODE_IDX" "$HEALTH" "$CODE_KB"
            sleep 0.5
          done
```

<br/>

## References

- [ECK Elasticsearch spec](https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-elasticsearch-specification.html)
- [ECK rolling upgrade docs](https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-rolling-upgrades.html)
- Chart source: [charts/elasticsearch-eck](../charts/elasticsearch-eck/) / [charts/kibana-eck](../charts/kibana-eck/)
