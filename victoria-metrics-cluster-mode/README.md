# VictoriaMetrics Cluster Mode — Full AZ-Isolated Observability

A complete replacement for the `prometheus-agent-mode` playground, offering end-to-end AZ isolation for the entire monitoring pipeline: metrics collection, ingestion, storage, querying, and rule execution.

## Architecture

```
                  ┌────────────────────────┐
                  │  VMAlert (random AZ)   │
                  │  reads: fed. vmselect  │
                  │  writes: vmagent svc   │
                  └────────┬───────────────┘
                           │ (PreferClose)
                  ┌────────▼───────────────┐
                  │  Federated vmselect    │
                  │  3 replicas, spread    │
                  │  trafficDist=Prefer    │
                  └──┬─────┬─────┬────────┘
                     │     │     │
         ┌───────────┘     │     └───────────┐
         ▼                 ▼                  ▼
   ┌──────────┐     ┌──────────┐      ┌──────────┐
   │VMCluster │     │VMCluster │      │VMCluster │
   │eu-west-1a│     │eu-west-1b│      │eu-west-1c│
   │insert/   │     │insert/   │      │insert/   │
   │storage/  │     │storage/  │      │storage/  │
   │select    │     │select    │      │select    │
   └────▲─────┘     └────▲─────┘      └────▲─────┘
        │                │                  │
   ┌────┴─────┐     ┌────┴─────┐      ┌────┴─────┐
   │VMAgent 1a│     │VMAgent 1b│      │VMAgent 1c│
   │catch-all │     │          │      │          │
   └──────────┘     └──────────┘      └──────────┘
```

### How It Differs from prometheus-agent-mode

The `prometheus-agent-mode` playground demonstrated AZ-aware **collection** but left cross-AZ **ingestion** unsolved — the centralized Prometheus server could land in any AZ, so remote-write traffic from agents still crossed AZ boundaries.

This platform solves the full path:

| Layer       | prometheus-agent-mode        | victoria-metrics-cluster-mode           |
|-------------|------------------------------|-----------------------------------------|
| Collection  | Per-AZ PrometheusAgent       | Per-AZ VMAgent                          |
| Ingestion   | Single Prometheus (any AZ)   | Per-AZ vminsert (pinned to AZ)          |
| Storage     | Single Prometheus (any AZ)   | Per-AZ vmstorage (pinned to AZ)         |
| Query       | Single Prometheus            | Federated vmselect (PreferClose)        |
| Rules       | Central Prometheus server    | VMAlert → federated vmselect            |

### Key Design Decisions

- **Per-AZ VMAgent → per-AZ vminsert**: Each agent writes to its local vminsert, keeping metrics within the AZ from collection through storage.
- **Federated vmselect (multi-level cluster setup)**: A standalone Deployment (not a VMCluster component) that uses `-storageNode` to query per-AZ vmselect services on their clusternative port (8401). Spread across AZs with `topologySpreadConstraints`. The Service uses `trafficDistribution: PreferClose` so clients query their local replica first. See [multi-level cluster setup](https://docs.victoriametrics.com/victoriametrics/cluster-victoriametrics/#multi-level-cluster-setup).
- **VMAlert writes back via PreferClose**: VMAlert communicates with the federated vmselect for reads and writes recording rule results to a catch-all VMAgent Service (also PreferClose), minimizing cross-AZ traffic.
- **Env var substitution in relabeling**: VMAgent supports `%{ZONE_NAME}%` syntax in relabel configs. Combined with Kubernetes downwardAPI (`metadata.labels['topology.kubernetes.io/zone']`), this eliminates the need for hardcoded zone values in relabel regex — only the `DEDICATED_AZ_PLACEMENT` env var differs per overlay.
- **Catch-all agent (1a)**: The eu-west-1a agent sets `DEDICATED_AZ_PLACEMENT='|'`, which makes the regex `(^(eu-west-1a|)$)` — matching both the zone name and empty strings (for targets without AZ metadata).
- **prometheus-operator coexistence**: kube-prometheus-stack provides CRDs (ServiceMonitor, PodMonitor, PrometheusRule) + ServiceMonitors + recording/alerting rules. The victoriametrics-operator auto-converts these to VM-native CRDs (VMServiceScrape, VMRule, etc.).

### Kubelet Scraping

Uses `VMNodeScrape` CRDs (native VM operator resource) instead of the kube-prometheus-stack kubelet ServiceMonitor, because Endpoints/EndpointSlices don't carry topology labels. Three VMNodeScrapes mirror the original endpoints:

| VMNodeScrape       | Path               | Notes                              |
|--------------------|--------------------|------------------------------------|
| `kubelet`          | `/metrics`         | Drops high-cardinality CSI/storage buckets |
| `kubelet-cadvisor` | `/metrics/cadvisor`| 10s interval; drops unused container metrics |
| `kubelet-probes`   | `/metrics/probes`  | No extra metric relabelings        |

The VMAgent's `nodeScrapeRelabelTemplate` handles AZ filtering for these via node topology labels.

## Components

### Helm Charts (via Helmfile)

1. **kube-prometheus-stack** v82.10.3 — operator + CRDs + ServiceMonitors + PrometheusRules + node-exporter + kube-state-metrics. Prometheus/Alertmanager/Grafana disabled.
2. **victoria-metrics-k8s-stack** v0.72.4 — victoriametrics-operator only. All VM instances, rules, dashboards, and scrape targets disabled (managed via kustomize). Chart's own ServiceMonitors disabled to avoid collision with kube-prometheus-stack.

### Base Resources (`base/`)

- **Namespace**: `monitoring`
- **RBAC**: ServiceAccount `vmagent-vm` + ClusterRole + ClusterRoleBinding + namespaced Role/RoleBinding for secrets/configmaps access (config-reloader)
- **Federated vmselect**: Raw Deployment (3 replicas, topology spread) + Service (PreferClose) querying per-AZ vmselects via multi-level cluster setup
- **VMAlert**: Reads from federated vmselect, writes back to VMAgent catch-all Service
- **Catch-all Service**: Selects all VMAgent pods (`vm_agent_federation: "true"`) with PreferClose
- **VMNodeScrape (kubelet)**: 3 resources for kubelet metrics, cadvisor, and probes
- **Gateway + HTTPRoutes**: Exposes federated vmselect and VMAlert via nip.io

### Per-AZ VMClusters (`clusters/`)

Uses a kustomize base + overlay pattern:

- **Base template** (`clusters/base/`): VMCluster CRD with `PLACEHOLDER` zone nodeSelectors + HTTPRoute template for per-AZ vmselect access
- **Overlays** (`clusters/overlays/eu-west-1{a,b,c}/`): Each overlay applies `namePrefix` and patches zone nodeSelector, HTTPRoute hostname and backend ref

Each VMCluster creates vminsert, vmstorage (5Gi), and vmselect — all pinned to their AZ via `nodeSelector`. The vmselect exposes the clusternative protocol via `extraArgs.clusternativeListenAddr: ":8401"` for multi-level federation.

### Per-AZ VMAgents (`agents/`)

Uses a kustomize base + overlay pattern:

- **Base template** (`agents/base/`): VMAgent CRD with `PLACEHOLDER` values for zone affinity, externalLabels, `DEDICATED_AZ_PLACEMENT` env, and remoteWrite URL. All relabel templates use `%{ZONE_NAME}%{DEDICATED_AZ_PLACEMENT}%` env var substitution.
- **Overlays** (`agents/overlays/eu-west-1{a,b,c}/`): Each overlay patches zone-specific values. Only 4 JSON patches needed per overlay (affinity, externalLabels, env, remoteWrite URL).

Each VMAgent: 2 replicas, 1 shard, 60s scrape interval, pinned to its AZ. The eu-west-1a agent is the catch-all for targets without AZ metadata.

## Usage

```bash
# Deploy everything (operators + base + agents)
make deploy

# Deploy individual components
make deploy-operator
make deploy-base
make deploy-clusters
make deploy-agents

# Check status and access URLs
make status

# Tear down everything
make destroy

# Render kustomize manifests without applying
make render
```

## Makefile Targets

| Target             | Description                                      |
|--------------------|--------------------------------------------------|
| `deploy`           | Deploy everything (operators + base + clusters + agents) |
| `deploy-operator`  | Install both operators via helmfile               |
| `deploy-base`      | Apply base resources (federated vmselect, VMAlert, gateway) |
| `deploy-clusters`  | Apply per-AZ VMCluster overlays                  |
| `deploy-agents`    | Apply per-AZ VMAgent overlays                    |
| `destroy`          | Tear down everything (reverse order)             |
| `destroy-agents`   | Remove per-AZ VMAgents                           |
| `destroy-clusters` | Remove per-AZ VMClusters                         |
| `destroy-base`     | Remove base resources                            |
| `destroy-operator` | Uninstall operators via helmfile                  |
| `status`           | Show VM resources and access URLs                |
| `render`           | Render all kustomize manifests to stdout          |
| `help`             | List all targets                                 |

## Access URLs

Once deployed, the following endpoints are available from the host:

| Service              | URL                                                         |
|----------------------|-------------------------------------------------------------|
| Federated vmselect   | http://vmselect.127.0.0.1.nip.io/select/0/vmui/       |
| VMAlert              | http://vmalert.127.0.0.1.nip.io                            |
| vmselect (eu-west-1a)| http://vmselect-1a.127.0.0.1.nip.io/select/0/vmui/   |
| vmselect (eu-west-1b)| http://vmselect-1b.127.0.0.1.nip.io/select/0/vmui/   |
| vmselect (eu-west-1c)| http://vmselect-1c.127.0.0.1.nip.io/select/0/vmui/   |

## File Structure

```
victoria-metrics-cluster-mode/
├── Makefile
├── README.md
├── vmagent-zone-a.yaml                    # Reference example (not deployed)
├── helmfile.yaml                          # kube-prometheus-stack + victoria-metrics-k8s-stack
├── values/
│   ├── kube-prometheus-stack.yaml         # Operator + CRDs + ServiceMonitors + rules
│   └── victoria-metrics-k8s-stack.yaml    # Operator-only (all instances disabled)
├── base/
│   ├── kustomization.yaml
│   ├── namespace.yaml                     # monitoring
│   ├── rbac.yaml                          # SA + ClusterRole for vmagent-vm
│   ├── vmselect-federated.yaml            # Federated vmselect Deployment + Service
│   ├── vmalert.yaml                       # VMAlert CRD
│   ├── vmagent-catchall-service.yaml      # Catch-all Service for VMAgents
│   ├── vmnodescrape-kubelet.yaml          # Kubelet VMNodeScrape (metrics, cadvisor, probes)
│   └── gateway.yaml                       # Gateway + HTTPRoutes
├── clusters/
│   ├── base/
│   │   ├── kustomization.yaml
│   │   ├── vmcluster.yaml                 # VMCluster template (insert/storage/select)
│   │   └── httproute.yaml                 # Per-AZ vmselect HTTPRoute template
│   └── overlays/
│       ├── eu-west-1a/
│       │   └── kustomization.yaml         # Zone affinity + vmselect-1a hostname
│       ├── eu-west-1b/
│       │   └── kustomization.yaml
│       └── eu-west-1c/
│           └── kustomization.yaml
└── agents/
    ├── base/
    │   ├── kustomization.yaml
    │   └── vmagent.yaml                   # VMAgent template (env var substitution)
    └── overlays/
        ├── eu-west-1a/
        │   └── kustomization.yaml         # Catch-all: DEDICATED_AZ_PLACEMENT='|'
        ├── eu-west-1b/
        │   └── kustomization.yaml
        └── eu-west-1c/
            └── kustomization.yaml
```
