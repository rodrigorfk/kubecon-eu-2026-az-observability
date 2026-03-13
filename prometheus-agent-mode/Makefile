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

deploy-operator: ## Install prometheus-operator via helmfile
	@$(KUBECTL) apply -f base/namespace.yaml > /dev/null
	@echo " ✓ Namespace ready"
	@helmfile --file helmfile.yaml sync --quiet
	@echo " ✓ Helmfile sync complete"
	@echo "Waiting for prometheus-operator components..."
	@$(KUBECTL) -n monitoring rollout status deployment/kube-prometheus-stack-operator --timeout=$(TIMEOUT) > /dev/null
	@echo " ✓ prometheus-operator ready"
	@$(KUBECTL) -n monitoring rollout status daemonset/kube-prometheus-stack-prometheus-node-exporter --timeout=$(TIMEOUT) > /dev/null
	@echo " ✓ node-exporter ready"
	@$(KUBECTL) -n monitoring rollout status deployment/kube-prometheus-stack-kube-state-metrics --timeout=$(TIMEOUT) > /dev/null
	@echo " ✓ kube-state-metrics ready"

deploy-base: ## Apply base resources (namespace, RBAC, central Prometheus)
	@$(KUBECTL) apply -k base/ > /dev/null
	@echo " ✓ Base resources applied"
	@echo "Waiting for Prometheus server..."
	@$(KUBECTL) -n monitoring wait --for=jsonpath='{.status.availableReplicas}'=1 \
		prometheus/prometheus-server --timeout=$(TIMEOUT) > /dev/null
	@$(KUBECTL) -n monitoring rollout status statefulset/prometheus-prometheus-server --timeout=$(TIMEOUT) > /dev/null
	@echo " ✓ Prometheus server ready"

deploy-agents: ## Apply per-AZ PrometheusAgent overlays
	@for zone in $(ZONES); do \
		$(KUBECTL) apply -k agents/overlays/$$zone/ > /dev/null; \
		echo " ✓ Agent $$zone applied"; \
	done
	@echo "Waiting for agents..."
	@for zone in $(ZONES); do \
		$(KUBECTL) -n monitoring wait --for=jsonpath='{.status.availableReplicas}'=1 \
			prometheusagent/$$zone-prometheus-agent --timeout=$(TIMEOUT) > /dev/null; \
		$(KUBECTL) -n monitoring rollout status statefulset/prom-agent-$$zone-prometheus-agent --timeout=$(TIMEOUT) > /dev/null; \
		echo " ✓ Agent $$zone ready"; \
	done

# ──────────────────────────────────────────────
# Destroy (reverse order)
# ──────────────────────────────────────────────

destroy: destroy-agents destroy-base destroy-operator ## Tear down everything

destroy-agents: ## Remove per-AZ agents
	@for zone in $(ZONES); do \
		$(KUBECTL) delete -k agents/overlays/$$zone/ --ignore-not-found > /dev/null; \
		echo " ✓ Agent $$zone removed"; \
	done

destroy-base: ## Remove base resources
	@$(KUBECTL) delete -k base/ --ignore-not-found > /dev/null
	@echo " ✓ Base resources removed"

destroy-operator: ## Uninstall prometheus-operator via helmfile
	@helmfile --file helmfile.yaml destroy --quiet
	@echo " ✓ Helm releases removed"

# ──────────────────────────────────────────────
# Observe
# ──────────────────────────────────────────────

status: ## Show Prometheus and PrometheusAgent resources
	@echo "=== Prometheus Server ==="
	@$(KUBECTL) -n monitoring get prometheus
	@echo ""
	@echo "=== Prometheus Agents ==="
	@$(KUBECTL) -n monitoring get prometheusagent
	@echo ""
	@echo "=== Pods ==="
	@$(KUBECTL) -n monitoring get pods -l 'app.kubernetes.io/name in (prometheus,prometheus-agent)' -o wide
	@echo ""
	@echo "=== Gateway & Routes ==="
	@$(KUBECTL) -n monitoring get gateway,httproute
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
	@$(KUBECTL) kustomize base/
	@for zone in $(ZONES); do \
		echo ""; \
		echo "--- agent: $$zone ---"; \
		$(KUBECTL) kustomize agents/overlays/$$zone/; \
	done

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-20s %s\n", $$1, $$2}'
