# Envoy Gateway

Ingress controller for the playground cluster using [Envoy Gateway](https://gateway.envoyproxy.io/) and the [Gateway API](https://gateway-api.sigs.k8s.io/).

## What Gets Deployed

1. **Envoy Gateway** (v1.7.1) — installed via Helmfile into `envoy-gateway-system` namespace
2. **EnvoyProxy** resource — pins the Envoy data plane pod to the Kind control-plane node labeled `ingress-ready: "true"`, and configures a NodePort service on port `30080`
3. **GatewayClass `eg`** — references the EnvoyProxy config; all Gateways in the cluster use this class
4. **Shared Gateway `playground`** — single HTTP listener on port 80 in `envoy-gateway-system`, accepts HTTPRoutes from all namespaces

## How Ingress Works

The Kind cluster maps `hostPort:80` on the first control-plane node to `containerPort:30080`. Envoy Gateway runs as a NodePort service bound to that same port:

```
Host machine :80  →  Kind node :30080  →  Envoy proxy :10080  →  upstream services
```

The shared `playground` Gateway is the single entry point for all `*.127.0.0.1.nip.io` hostnames. Each platform and workload creates its own HTTPRoutes that attach to this Gateway via a cross-namespace `parentRef`.

Examples:
- `http://prometheus.127.0.0.1.nip.io` — Prometheus server (prometheus-agent-mode)
- `http://vmselect.127.0.0.1.nip.io` — Federated vmselect (victoria-metrics-cluster-mode)
- `http://podinfo.127.0.0.1.nip.io` — Podinfo workload

## Usage

This component is automatically deployed by the root `make create`. To manage it independently:

```bash
# Deploy
make deploy

# Check status
make status

# Remove
make destroy
```

## Makefile Targets

| Target    | Description                            |
|-----------|----------------------------------------|
| `deploy`  | Install Envoy Gateway and base resources |
| `destroy` | Remove Envoy Gateway                   |
| `status`  | Show Envoy Gateway pods and GatewayClass |
| `help`    | List all targets                       |

## File Structure

```
envoy-gateway/
├── Makefile
├── helmfile.yaml                 # Envoy Gateway helm chart (v1.7.1)
├── values/
│   └── envoy-gateway.yaml        # Chart values
└── base/
    ├── kustomization.yaml
    └── gateway.yaml              # EnvoyProxy + GatewayClass "eg" + shared Gateway "playground"
```
