# Envoy Gateway

Ingress controller for the playground cluster using [Envoy Gateway](https://gateway.envoyproxy.io/) and the [Gateway API](https://gateway-api.sigs.k8s.io/).

## What Gets Deployed

1. **Envoy Gateway** (v1.7.1) — installed via Helmfile into `envoy-gateway-system` namespace
2. **EnvoyProxy** resource — pins the Envoy data plane pod to the Kind control-plane node labeled `ingress-ready: "true"`, and configures a NodePort service on port `30080`
3. **GatewayClass `eg`** — references the EnvoyProxy config; all Gateways in the cluster use this class

## How Ingress Works

The Kind cluster maps `hostPort:80` on the first control-plane node to `containerPort:30080`. Envoy Gateway runs as a NodePort service bound to that same port:

```
Host machine :80  →  Kind node :30080  →  Envoy proxy :10080  →  upstream services
```

Any HTTPRoute using the `eg` GatewayClass becomes accessible from the host via `*.127.0.0.1.nip.io` hostnames. For example:

- `http://prometheus.127.0.0.1.nip.io` — Prometheus server
- `http://prometheus-agent-1a.127.0.0.1.nip.io` — Agent in eu-west-1a

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
    └── gateway.yaml              # EnvoyProxy (NodePort on 30080) + GatewayClass "eg"
```
