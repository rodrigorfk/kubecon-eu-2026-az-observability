# Prometheus Agent Mode — AZ-Aware Collection

Deploys a per-AZ Prometheus agent architecture where each availability zone runs its own agent that scrapes only local targets and forwards metrics via remote-write to a centralized Prometheus server.

## Architecture

```
                  ┌──────────────────────┐
                  │   Prometheus Server  │
                  │ (remote-write recv)  │
                  │    retention: 7d     │
                  └──────▲───▲───▲───────┘
                         │   │   │
            remote-write │   │   │ remote-write
                         │   │   │
           ┌─────────────┘   │   └──────────────┐
           │                 │                  │
    ┌──────┴──────┐    ┌─────┴───────┐   ┌──────┴──────┐
    │  Agent 1a   │    │  Agent 1b   │   │  Agent 1c   │
    │ (eu-west-1a)│    │ (eu-west-1b)│   │ (eu-west-1c)│
    └──────┬──────┘    └──────┬──────┘   └──────┬──────┘
           │                  │                 │
     scrapes only       scrapes only       scrapes only
     local pods         local pods         local pods
```

### Key Design Decisions

- **Agents scrape, server stores**: The central Prometheus has `enableRemoteWriteReceiver: true` and does **not** scrape anything itself. All scraping is done by the per-AZ agents.
- **AZ pinning**: Each agent has a `nodeSelector` for its zone, ensuring it only runs on nodes within that AZ.
- **AZ-aware filtering**: A default `scrapeClass` uses relabel rules to keep only targets whose `topology.kubernetes.io/zone` annotation or label matches the agent's zone. This prevents cross-AZ scraping.
- **External labels**: Each agent stamps metrics with `availability_zone: eu-west-1{a,b,c}` and `cluster: playground`.

### Limitations

This vanilla Prometheus setup is **illustrative** — it demonstrates AZ-aware metrics collection at the agent level, but it does **not** solve cross-AZ data ingestion. The centralized Prometheus server is a single instance that can be scheduled in any AZ, meaning agents from other zones still send remote-write traffic across AZ boundaries.

To achieve full AZ isolation (both collection and ingestion), a more robust platform using per-AZ storage backends (e.g., VictoriaMetrics with per-AZ vminsert/vmstorage stacks and federated vmselect) will be built as a separate playground.

## Components

### kube-prometheus-stack (Helmfile)

Installs the Prometheus Operator (v82.10.3) with only the operator itself, node-exporter, and kube-state-metrics enabled. Prometheus and Grafana from the chart are disabled — we manage our own Prometheus resources.

### Base Resources (`base/`)

- **Namespace**: `monitoring`
- **RBAC**: ServiceAccounts, ClusterRoles, and ClusterRoleBindings for both `prometheus-server` and `prometheus-agent`
- **Prometheus Server**: Single-replica Prometheus with remote-write receiver enabled, 10Gi persistent storage, 7d retention
- **Gateway + HTTPRoute**: Exposes the server at `http://prometheus.127.0.0.1.nip.io`

### Per-AZ Agents (`agents/`)

Uses a kustomize base + overlay pattern:

- **Base template** (`agents/base/`): Defines a `PrometheusAgent` with `PLACEHOLDER` values for zone, external labels, and relabel regex
- **Overlays** (`agents/overlays/eu-west-1{a,b,c}/`): Each overlay applies a `namePrefix` and JSON patches to substitute the zone-specific values

Each agent gets:
- A `PrometheusAgent` CRD pinned to its AZ
- A `Service` for scraping the agent's own metrics
- An `HTTPRoute` at `http://prometheus-agent-{1a,1b,1c}.127.0.0.1.nip.io`

## Usage

```bash
# Deploy everything (operator + base + agents)
make deploy

# Deploy individual components
make deploy-operator
make deploy-base
make deploy-agents

# Check status and access URLs
make status

# Tear down everything
make destroy

# Render kustomize manifests without applying
make render
```

## Makefile Targets

| Target            | Description                                    |
|-------------------|------------------------------------------------|
| `deploy`          | Deploy everything (operator + base + agents)   |
| `deploy-operator` | Install prometheus-operator via helmfile        |
| `deploy-base`     | Apply namespace, RBAC, Prometheus server, gateway |
| `deploy-agents`   | Apply per-AZ PrometheusAgent overlays          |
| `destroy`         | Tear down everything (reverse order)           |
| `destroy-agents`  | Remove per-AZ agents                           |
| `destroy-base`    | Remove base resources                          |
| `destroy-operator`| Uninstall prometheus-operator via helmfile      |
| `status`          | Show resources and access URLs                 |
| `render`          | Render all kustomize manifests to stdout        |
| `help`            | List all targets                               |

## Access URLs

Once deployed, the following endpoints are available from the host:

| Service              | URL                                            |
|----------------------|------------------------------------------------|
| Prometheus Server    | http://prometheus.127.0.0.1.nip.io             |
| Agent (eu-west-1a)   | http://prometheus-agent-1a.127.0.0.1.nip.io    |
| Agent (eu-west-1b)   | http://prometheus-agent-1b.127.0.0.1.nip.io    |
| Agent (eu-west-1c)   | http://prometheus-agent-1c.127.0.0.1.nip.io    |

## File Structure

```
prometheus-agent-mode/
├── Makefile
├── helmfile.yaml                         # kube-prometheus-stack v82.10.3
├── values/
│   └── kube-prometheus-stack.yaml        # Chart values (operator-only mode)
├── base/
│   ├── kustomization.yaml
│   ├── namespace.yaml                    # monitoring namespace
│   ├── rbac.yaml                         # ServiceAccounts + RBAC
│   ├── prometheus-server.yaml            # Central Prometheus + Service
│   └── gateway.yaml                      # Gateway + HTTPRoute for server
└── agents/
    ├── base/
    │   ├── kustomization.yaml
    │   ├── prometheus-agent.yaml          # PrometheusAgent template (PLACEHOLDER values)
    │   ├── service.yaml                   # Agent service template
    │   └── httproute.yaml                 # Agent HTTPRoute template
    └── overlays/
        ├── eu-west-1a/
        │   └── kustomization.yaml         # namePrefix + zone patches
        ├── eu-west-1b/
        │   └── kustomization.yaml
        └── eu-west-1c/
            └── kustomization.yaml
```
