# unity-mcp-server

Helm chart for the [Unity MCP Server](https://github.com/CoplayDev/unity-mcp) — a [Model Context Protocol](https://modelcontextprotocol.io/) bridge for the Unity editor, served over [FastMCP's](https://gofastmcp.com/) StreamableHTTP transport.

## Bring your own image

This chart ships **no default image** and does not depend on an upstream Docker build. You must build your own image from the upstream repo and push it to a registry your cluster can pull from.

Minimum Dockerfile:

```dockerfile
FROM python:3.12-slim
RUN pip install --no-cache-dir uv
WORKDIR /app
RUN git clone --depth 1 https://github.com/CoplayDev/unity-mcp.git .
# FastMCP 3.2+ is strongly recommended — earlier versions have looser
# handling of session-less GET /mcp requests (see Known limitations).
RUN uv pip install --system --upgrade fastmcp
EXPOSE 8080
# Command/args are driven by the Helm chart (values.yaml: command/args).
```

Push to your registry (GHCR, ECR, Harbor, …) and set `image.repository` / `image.tag` to whatever you pushed. `YOUR_TAG` in every example below is a placeholder — substitute your build tag (e.g. the upstream release version, a git SHA, a CI build number, …).

```yaml
image:
  repository: ghcr.io/yourorg/unity-mcp-server
  tag: YOUR_TAG
```

## What it deploys

| Resource | API | Purpose |
|---|---|---|
| `Deployment` | `apps/v1` | Unity MCP server container (FastMCP HTTP transport) |
| `Service` | `v1` | ClusterIP by default |
| `Secret` | `v1` | Optional — `MCP_API_KEY` (when `apiKey.enabled` and no `existingSecret`) |
| `HTTPRoute` | `gateway.networking.k8s.io/v1` | Optional — Gateway API ingress (`httproute.enabled`) |
| `Ingress` | `networking.k8s.io/v1` | Optional — legacy Ingress (`ingress.enabled`) |
| `ProxySettingsPolicy` | `gateway.nginx.org/v1alpha1` | Optional — NGINX Gateway Fabric SSE buffering off |
| `ServiceAccount` | `v1` | Optional — dedicated SA for IRSA / image pull secret scoping (`serviceAccount.create`) |
| `NetworkPolicy` | `networking.k8s.io/v1` | Optional — pod-level ingress/egress lock-down (`networkPolicy.enabled`) |

## Versioning

- Chart `version` — this chart's own SemVer, bumped on every change.
- `appVersion` — the upstream `CoplayDev/unity-mcp` release this chart was tested against.

## Prerequisites

- Kubernetes **1.25+**
- An image you built from upstream (see above)
- For `httproute.enabled`: a Gateway API–compliant controller with a ready `Gateway`
- For `nginxGatewayFabric.proxySettings.enabled`: NGINX Gateway Fabric specifically
- For `ingress.enabled`: an Ingress controller

## Install

```bash
helm install unity-mcp oci://ghcr.io/somaz94/charts/unity-mcp-server \
  --version 0.1.0 \
  --namespace mcp --create-namespace \
  --set image.repository=ghcr.io/yourorg/unity-mcp-server \
  --set image.tag=YOUR_TAG \
  --set apiKey.value=CHANGE_ME
```

## Required values

- `image.repository` — your registry path
- `image.tag` — pinned tag
- `apiKey.value` or `apiKey.existingSecret` — when `apiKey.enabled: true` (default)

## Examples

### Minimal (cluster-internal access only)

```yaml
image:
  repository: ghcr.io/yourorg/unity-mcp-server
  tag: YOUR_TAG
apiKey:
  value: super-secret-key
```

### External access via NGINX Gateway Fabric (SSE-friendly)

```yaml
image:
  repository: ghcr.io/yourorg/unity-mcp-server
  tag: YOUR_TAG
apiKey:
  existingSecret: unity-mcp-api-key   # keys: api-key
imagePullSecrets:
  - name: ghcr-pull-secret
httproute:
  enabled: true
  parentRefs:
    - name: ngf
      namespace: nginx-gateway
  hostnames:
    - unity-mcp.example.com
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      timeouts:
        request: 300s        # long-lived SSE connections
        backendRequest: 300s
      backendRefs:
        - {}
nginxGatewayFabric:
  proxySettings:
    enabled: true            # turn off response buffering for SSE
```

### Legacy Ingress (ingress-nginx)

```yaml
image:
  repository: ghcr.io/yourorg/unity-mcp-server
  tag: YOUR_TAG
apiKey:
  value: super-secret-key
ingress:
  enabled: true
  className: nginx
  host: unity-mcp.example.com
  annotations:
    nginx.ingress.kubernetes.io/proxy-buffering: "off"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "300"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "300"
  tls:
    - hosts: [unity-mcp.example.com]
      secretName: unity-mcp-tls
```

## Values reference

Top-level blocks:

| Block | Purpose |
|---|---|
| `image.{repository,tag,pullPolicy}` | Your self-built container image (**required**) |
| `imagePullSecrets` | Extra pull secrets |
| `containerPort` | FastMCP listen port (default 8080) |
| `service.{type,port,nodePort,annotations}` | Kubernetes Service shape |
| `command` / `args` | Container entrypoint; defaults match upstream `mcp-for-unity` |
| `apiKey.{enabled,value,existingSecret,secretKey}` | `MCP_API_KEY` wiring |
| `env[]` | Extra environment variables |
| `resources` | Requests / limits |
| `livenessProbe` / `readinessProbe` | **tcpSocket by default** — do not switch to `httpGet /mcp` (see Known limitations) |
| `httproute.*` / `ingress.*` | Two mutually compatible ingress paths |
| `nginxGatewayFabric.proxySettings.*` | NGF `ProxySettingsPolicy` (`buffering.disable: true`) |
| `serviceAccount.*` | Optional dedicated SA (IRSA / Workload Identity / imagePullSecrets) |
| `networkPolicy.*` | Optional `NetworkPolicy` (native `ingress`/`egress` rules) |
| `commonLabels` / `commonAnnotations` / `resourceMetadata.*` | Labels and annotations per resource kind |
| `specExtra` / `podTemplateExtra` / `kubernetesExtra` | Escape hatches |

## Known limitations

- **StreamableHTTP 400 on `GET /mcp` without a session** is spec-compliant. FastMCP requires clients to first `POST /mcp` with `initialize` (receiving an `Mcp-Session-Id` header) and then open the SSE stream with that header. Pre-session `GET /mcp` probes will return 400 and clutter logs — not a bug. This is why the default probes are `tcpSocket`, not `httpGet`. FastMCP 3.2+ improves the error responses.
- **`/.well-known/oauth-protected-resource` 404** is also spec-compliant — it declares the server is not OAuth-protected. FastMCP 3.2+ adds a cleaner default handler.
- **No default image**. If you want the upstream FastMCP bootstrap to Just Work, wrap it in your own Dockerfile and CI. See the "Bring your own image" section.

## Contributing

Run locally:

```bash
make lint CHART=unity-mcp-server
make template CHART=unity-mcp-server
make validate CHART=unity-mcp-server
```
