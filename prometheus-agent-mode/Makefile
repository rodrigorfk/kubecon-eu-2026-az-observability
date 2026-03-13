KUBECONFIG ?= ../kubeconfig
CONTEXT    ?= kind-playground
KUBECTL    := kubectl --context $(CONTEXT)
TIMEOUT    := 120s

ZONES := eu-west-1a eu-west-1b eu-west-1c

export KUBECONFIG

.PHONY: all deploy deploy-operator deploy-base deploy-agents \
        destroy destroy-agents destroy-base destroy-operator \
        status render help

all: deploy ## Full deploy: operator + base + agents

# ──────────────────────────────────────────────
# Deploy
# ──────────────────────────────────────────────

deploy: deploy-operator deploy-base deploy-agents ## Deploy everything

deploy-operator: ## Install envoy-gateway + prometheus-operator via helmfile
	$(KUBECTL) apply -f base/namespace.yaml
	helmfile --file helmfile.yaml sync
	@echo "Waiting for envoy-gateway to be ready..."
	$(KUBECTL) -n envoy-gateway-system rollout status deployment/envoy-gateway --timeout=$(TIMEOUT)
	@echo "Waiting for prometheus-operator to be ready..."
	$(KUBECTL) -n monitoring rollout status deployment/kube-prometheus-stack-operator --timeout=$(TIMEOUT)
	$(KUBECTL) -n monitoring rollout status daemonset/kube-prometheus-stack-prometheus-node-exporter --timeout=$(TIMEOUT)
	$(KUBECTL) -n monitoring rollout status deployment/kube-prometheus-stack-kube-state-metrics --timeout=$(TIMEOUT)

deploy-base: ## Apply base resources (namespace, RBAC, central Prometheus)
	$(KUBECTL) apply -k base/
	@echo "Waiting for Prometheus server to be ready..."
	$(KUBECTL) -n monitoring wait --for=jsonpath='{.status.availableReplicas}'=1 \
		prometheus/prometheus-server --timeout=$(TIMEOUT)
	$(KUBECTL) -n monitoring rollout status statefulset/prometheus-prometheus-server --timeout=$(TIMEOUT)

deploy-agents: ## Apply per-AZ PrometheusAgent overlays
	@for zone in $(ZONES); do \
		echo "Deploying agent for $$zone..."; \
		$(KUBECTL) apply -k agents/overlays/$$zone/; \
	done
	@echo "Waiting for all agents to be ready..."
	@for zone in $(ZONES); do \
		echo "  Waiting for $$zone agent..."; \
		$(KUBECTL) -n monitoring wait --for=jsonpath='{.status.availableReplicas}'=1 \
			prometheusagent/$$zone-prometheus-agent --timeout=$(TIMEOUT); \
		$(KUBECTL) -n monitoring rollout status statefulset/prom-agent-$$zone-prometheus-agent --timeout=$(TIMEOUT); \
	done

# ──────────────────────────────────────────────
# Destroy (reverse order)
# ──────────────────────────────────────────────

destroy: destroy-agents destroy-base destroy-operator ## Tear down everything

destroy-agents: ## Remove per-AZ agents
	@for zone in $(ZONES); do \
		echo "Removing agent for $$zone..."; \
		$(KUBECTL) delete -k agents/overlays/$$zone/ --ignore-not-found; \
	done

destroy-base: ## Remove base resources
	$(KUBECTL) delete -k base/ --ignore-not-found

destroy-operator: ## Uninstall prometheus-operator via helmfile
	helmfile --file helmfile.yaml destroy

# ──────────────────────────────────────────────
# Observe
# ──────────────────────────────────────────────

status: ## Show Prometheus and PrometheusAgent resources
	@echo "=== Prometheus Server ==="
	$(KUBECTL) -n monitoring get prometheus
	@echo ""
	@echo "=== Prometheus Agents ==="
	$(KUBECTL) -n monitoring get prometheusagent
	@echo ""
	@echo "=== Pods ==="
	$(KUBECTL) -n monitoring get pods -l 'app.kubernetes.io/name in (prometheus)' -o wide
	@echo ""
	@echo "=== Gateway & Routes ==="
	$(KUBECTL) -n monitoring get gateway,httproute
	@echo ""
	@echo "=== Access ==="
	@echo "  Prometheus Server: http://prometheus.127.0.0.1.nip.io"
	@for zone in $(ZONES); do \
		short=$$(echo $$zone | sed 's/.*-//'); \
		echo "  Agent $$zone:        http://prometheus-agent-$$short.127.0.0.1.nip.io"; \
	done

# ──────────────────────────────────────────────
# Render (dry-run)
# ──────────────────────────────────────────────

render: ## Render all kustomize manifests to stdout
	@echo "--- base ---"
	$(KUBECTL) kustomize base/
	@for zone in $(ZONES); do \
		echo ""; \
		echo "--- agent: $$zone ---"; \
		$(KUBECTL) kustomize agents/overlays/$$zone/; \
	done

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-20s %s\n", $$1, $$2}'
