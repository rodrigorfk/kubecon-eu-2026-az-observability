# Prometheus Agent Mode — AZ-Aware Collection

Deploys a per-AZ Prometheus agent architecture where each availability zone runs its own agent that scrapes only local targets and forwards metrics via remote-write to a centralized Prometheus server.

## Architecture

```
                  ┌──────────────────────┐
                  │   Prometheus Server  │
                  │ (remote-write recv)  │
                  │  retention: 7d       │
                  │  rules: ✓            │
                  └──────────────────────┘
                         ▲   ▲   ▲
                         │   │   │
            remote-write │   │   │ remote-write
                         │   │   │
           ┌─────────────┘   │   └──────────────┐
           │                 │                  │
    ┌──────┴──────┐   ┌──────┴──────┐   ┌───────┴─────┐
    │  Agent 1a   │   │  Agent 1b   │   │  Agent 1c   │
    │ (eu-west-1a)│   │ (eu-west-1b)│   │ (eu-west-1c)│
    │ + catch-all │   │             │   │             │
    └──────┬──────┘   └──────┬──────┘   └──────┬──────┘
           │                 │                 │
     scrapes local     scrapes local      scrapes local
     pods + kubelet    pods + kubelet     pods + kubelet
     + static targets
```

### Key Design Decisions

- **Agents scrape, server stores**: The central Prometheus has `enableRemoteWriteReceiver: true` and does **not** scrape anything itself. All scraping is done by the per-AZ agents.
- **Rules run on the server**: `PrometheusAgent` does not support rules. The server loads all `PrometheusRules` (via `ruleSelector: {}`) for recording and alerting rule evaluation.
- **AZ pinning**: Each agent has a `nodeSelector` for its zone, ensuring it only runs on nodes within that AZ.
- **AZ-aware filtering via scrapeClasses**: Two scrape classes handle different service discovery types:
  - `az-filter` (default) — filters by pod annotation, pod label, or EC2 AZ metadata
  - `az-filter-kubelet` — filters by node label; also carries `bearerTokenFile` and `tlsConfig` for kubelet auth
- **Catch-all agent (1a)**: The eu-west-1a agent also scrapes targets with empty topology labels (static/hostname-based and kube-apiserver targets that lack AZ metadata).
- **External labels**: Each agent stamps metrics with `availability_zone: eu-west-1{a,b,c}` and `cluster: playground`.

### Kubelet Scraping

The kube-prometheus-stack kubelet `ServiceMonitor` is **disabled** because the Endpoints/EndpointSlices it targets don't carry topology labels, making AZ-aware filtering impossible. Instead, we use `ScrapeConfig` resources with `kubernetes_sd` node role, which exposes `__meta_kubernetes_node_label_topology_kubernetes_io_zone`.

Three ScrapeConfigs mirror the original ServiceMonitor endpoints:

| ScrapeConfig       | Path               | Notes                              |
|--------------------|--------------------|------------------------------------|
| `kubelet`          | `/metrics`         | Drops high-cardinality CSI/storage buckets |
| `kubelet-cadvisor` | `/metrics/cadvisor`| 10s interval; drops unused container metrics |
| `kubelet-probes`   | `/metrics/probes`  | No extra metric relabelings        |

All three use the `az-filter-kubelet` scrapeClass, which provides SA token auth and CA certificate configuration.

The kubelet Endpoints/EndpointSlice sync by the operator is also disabled (`kubeletService.enabled: false`).

### Limitations

This vanilla Prometheus setup is **illustrative** — it demonstrates AZ-aware metrics collection at the agent level, but it does **not** solve cross-AZ data ingestion. The centralized Prometheus server is a single instance that can be scheduled in any AZ, meaning agents from other zones still send remote-write traffic across AZ boundaries.

To achieve full AZ isolation (both collection and ingestion), a more robust platform using per-AZ storage backends (e.g., VictoriaMetrics with per-AZ vminsert/vmstorage stacks and federated vmselect) will be built as a separate playground.

## Components

### kube-prometheus-stack (Helmfile)

Installs the Prometheus Operator (v82.10.3) with only the operator itself, node-exporter, and kube-state-metrics enabled. Prometheus, Alertmanager, and Grafana from the chart are disabled — we manage our own Prometheus resources.

Enabled ServiceMonitors from the chart: kubeApiServer, kubeControllerManager, coreDns, kubeEtcd, kubeScheduler, kubeProxy.

Disabled from the chart: kubelet (replaced by ScrapeConfigs), kubeletService sync (no longer needed).

### Base Resources (`base/`)

- **Namespace**: `monitoring`
- **RBAC**: ServiceAccounts, ClusterRoles, and ClusterRoleBindings for both `prometheus-server` and `prometheus-agent`
- **Prometheus Server**: Single-replica Prometheus with remote-write receiver enabled, 10Gi persistent storage, 7d retention, all PrometheusRules loaded
- **ScrapeConfig (kubelet)**: Three ScrapeConfigs for kubelet metrics, cadvisor, and probes using kubernetes_sd node role
- **Gateway + HTTPRoute**: Exposes the server at `http://prometheus.127.0.0.1.nip.io`

### Per-AZ Agents (`agents/`)

Uses a kustomize base + overlay pattern:

- **Base template** (`agents/base/`): Defines a `PrometheusAgent` with `PLACEHOLDER` values for zone, external labels, and relabel regex. Includes two scrapeClasses (`az-filter` and `az-filter-kubelet`) and selectors for ServiceMonitors, PodMonitors, and ScrapeConfigs.
- **Overlays** (`agents/overlays/eu-west-1{a,b,c}/`): Each overlay applies a `namePrefix` and JSON patches to substitute zone-specific values for both scrapeClasses.

Each agent gets:
- A `PrometheusAgent` CRD pinned to its AZ
- A `Service` for scraping the agent's own metrics
- An `HTTPRoute` at `http://prometheus-agent-{1a,1b,1c}.127.0.0.1.nip.io`

The eu-west-1a overlay has a wider regex that also matches empty topology labels, making it the catch-all for static targets.

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
| `deploy-base`     | Apply namespace, RBAC, Prometheus server, kubelet ScrapeConfigs, HTTPRoutes |
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
│   └── kube-prometheus-stack.yaml        # Chart values (operator-only, kubelet disabled)
├── base/
│   ├── kustomization.yaml
│   ├── namespace.yaml                    # monitoring namespace
│   ├── rbac.yaml                         # ServiceAccounts + RBAC
│   ├── prometheus-server.yaml            # Central Prometheus + Service (rules enabled)
│   ├── scrapeconfig-kubelet.yaml         # Kubelet ScrapeConfigs (metrics, cadvisor, probes)
│   └── httproute.yaml                    # HTTPRoutes for server and alertmanager
└── agents/
    ├── base/
    │   ├── kustomization.yaml
    │   ├── prometheus-agent.yaml          # PrometheusAgent template (2 scrapeClasses)
    │   ├── service.yaml                   # Agent service template
    │   └── httproute.yaml                 # Agent HTTPRoute template
    └── overlays/
        ├── eu-west-1a/
        │   └── kustomization.yaml         # namePrefix + zone patches + catch-all regex
        ├── eu-west-1b/
        │   └── kustomization.yaml
        └── eu-west-1c/
            └── kustomization.yaml
```
