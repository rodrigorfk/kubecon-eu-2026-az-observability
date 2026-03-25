# VictoriaMetrics Baseline — AZ-Unaware Observability

The **"before" state**. A single VictoriaMetrics stack with no availability zone awareness: one VMAgent scrapes all targets regardless of zone, and one VMCluster stores all metrics. Components are free to schedule on any node, generating high cross-AZ traffic as scrape agents pull from pods in remote zones and push metrics to ingestion endpoints that may also be in a different zone.

Use this platform to establish the cost baseline before applying AZ-aware optimizations. Compare `beyla_network_inter_zone_bytes_total` between this and `victoria-metrics-cluster-mode` to quantify the improvement.

## Architecture

```
              ┌──────────────────────────┐
              │  VMCluster (any AZ)      │
              │  vminsert / vmstorage    │
              │  vmselect                │
              └──────────▲───────────────┘
                         │ remote-write
              ┌──────────┴───────────────┐
              │  VMAgent (any AZ)        │
              │  scrapes all targets     │
              │  in all zones            │
              └──────────────────────────┘
```

No zone pinning. No AZ-aware filtering. No traffic distribution hints. Every component lands wherever the scheduler places it.

### How It Differs from victoria-metrics-cluster-mode

| Layer       | Baseline (this)              | AZ-Aware (cluster-mode)                 |
|-------------|------------------------------|-----------------------------------------|
| Collection  | 1 VMAgent (any AZ)           | 3 VMAgents (one per AZ, pinned)         |
| Ingestion   | 1 vminsert (any AZ)          | 3 vminserts (one per AZ, pinned)        |
| Storage     | 1 vmstorage (any AZ)         | 3 vmstorages (one per AZ, pinned)       |
| Query       | 1 vmselect (any AZ)          | Federated vmselect (PreferClose)        |
| Rules       | VMAlert → local vmselect     | VMAlert → federated vmselect            |
| Cross-AZ    | High (uncontrolled)          | Minimal (write path local to each AZ)  |

## Components

### Helm Charts (via Helmfile)

Same as `victoria-metrics-cluster-mode`:

1. **kube-prometheus-stack** v82.10.3 — operator + CRDs + ServiceMonitors + PrometheusRules + node-exporter + kube-state-metrics
2. **victoria-metrics-k8s-stack** v0.72.4 — victoriametrics-operator only

### Base Resources (`base/`)

- **Namespace**: `monitoring`
- **RBAC**: ServiceAccount `vmagent-vm` + ClusterRole + ClusterRoleBinding + Role/RoleBinding for config-reloader
- **VMCluster `vm-baseline`**: Single cluster with vminsert, vmstorage (5Gi), vmselect — no zone constraints
- **VMAgent `vmagent`**: 2 replicas, scrapes everything, remote-writes to `vminsert-vm-baseline`
- **VMAlert**: Reads from and writes back to `vmselect-vm-baseline`
- **VMNodeScrape (kubelet)**: 3 resources for kubelet metrics, cadvisor, and probes
- **HTTPRoutes**: vmselect, vmalert, alertmanager via nip.io

## Usage

```bash
# Deploy everything (operators + base + agents)
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

| Target             | Description                                      |
|--------------------|--------------------------------------------------|
| `deploy`           | Deploy everything (operators + base + agents)    |
| `deploy-operator`  | Install both operators via helmfile               |
| `deploy-base`      | Apply base resources (VMCluster, VMAlert, gateway) |
| `deploy-agents`    | Wait for VMAgent and VMAlert to become operational |
| `destroy`          | Tear down everything (reverse order)             |
| `destroy-agents`   | Remove VMAgent and VMAlert                       |
| `destroy-base`     | Remove base resources                            |
| `destroy-operator` | Uninstall operators via helmfile                  |
| `status`           | Show VM resources and access URLs                |
| `render`           | Render kustomize manifests to stdout              |
| `help`             | List all targets                                 |

## Access URLs

| Service      | URL                                              |
|--------------|--------------------------------------------------|
| vmselect     | http://vmselect.127.0.0.1.nip.io/select/0/vmui/ |
| VMAlert      | http://vmalert.127.0.0.1.nip.io                  |
| Alertmanager | http://alertmanager.127.0.0.1.nip.io             |

## File Structure

```
victoria-metrics-baseline/
├── Makefile
├── helmfile.yaml                         # kube-prometheus-stack + victoria-metrics-k8s-stack
├── values/
│   ├── kube-prometheus-stack.yaml        # Operator + CRDs + ServiceMonitors + rules
│   └── victoria-metrics-k8s-stack.yaml  # Operator-only (all instances disabled)
└── base/
    ├── kustomization.yaml
    ├── namespace.yaml                    # monitoring
    ├── rbac.yaml                         # ServiceAccount + RBAC for vmagent-vm
    ├── vmcluster.yaml                    # Single VMCluster (no zone constraints)
    ├── vmagent.yaml                      # Single VMAgent (no AZ filtering)
    ├── vmalert.yaml                      # VMAlert reading from vmselect-vm-baseline
    ├── vmnodescrape-kubelet.yaml         # Kubelet VMNodeScrape (metrics, cadvisor, probes)
    └── httproute.yaml                    # HTTPRoutes (vmselect, vmalert, alertmanager)
```
