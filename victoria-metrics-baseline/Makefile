KUBECONFIG ?= ../kubeconfig
CONTEXT    ?= kind-playground
KUBECTL    := kubectl --context $(CONTEXT)
TIMEOUT    := 180s

export KUBECONFIG

.PHONY: all deploy deploy-operator deploy-base deploy-agents \
        destroy destroy-agents destroy-base destroy-operator \
        status render help

all: deploy ## Full deploy: operator + base + agents

# ──────────────────────────────────────────────
# Deploy
# ──────────────────────────────────────────────

deploy: deploy-operator deploy-base deploy-agents ## Deploy everything

deploy-operator: ## Install prometheus-operator + victoriametrics-operator via helmfile
	@$(KUBECTL) apply -f base/namespace.yaml > /dev/null
	@echo " ✓ Namespace ready, starting operator deployment"
	@helmfile --file helmfile.yaml sync --quiet
	@echo " ✓ Helmfile sync complete"
	@echo "Waiting for prometheus-operator components..."
	@$(KUBECTL) -n monitoring rollout status deployment/kube-prometheus-stack-operator --timeout=$(TIMEOUT) > /dev/null
	@echo " ✓ prometheus-operator ready"
	@$(KUBECTL) -n monitoring rollout status daemonset/kube-prometheus-stack-prometheus-node-exporter --timeout=$(TIMEOUT) > /dev/null
	@echo " ✓ node-exporter ready"
	@$(KUBECTL) -n monitoring rollout status deployment/kube-prometheus-stack-kube-state-metrics --timeout=$(TIMEOUT) > /dev/null
	@echo " ✓ kube-state-metrics ready"
	@echo "Waiting for victoriametrics-operator..."
	@$(KUBECTL) -n monitoring rollout status deployment -l app.kubernetes.io/name=victoria-metrics-operator --timeout=$(TIMEOUT) > /dev/null
	@echo " ✓ victoriametrics-operator ready"

deploy-base: ## Apply base resources (VMCluster, VMAlert, gateway)
	@$(KUBECTL) apply -k base/ > /dev/null
	@echo " ✓ Base resources applied"
	@echo "Waiting for alertmanager..."
	@$(KUBECTL) -n monitoring rollout status statefulset/alertmanager-kube-prometheus-stack-alertmanager --timeout=$(TIMEOUT) > /dev/null
	@echo " ✓ Alertmanager ready"
	@echo "Waiting for VMCluster to become operational..."
	@$(KUBECTL) -n monitoring wait --for=jsonpath='{.status.updateStatus}'=operational \
		vmcluster/vm-baseline --timeout=$(TIMEOUT) > /dev/null
	@echo " ✓ VMCluster operational"

deploy-agents: ## Apply VMAgent and wait for it to become operational
	@echo "Waiting for VMAgent to become operational..."
	@$(KUBECTL) -n monitoring wait --for=jsonpath='{.status.updateStatus}'=operational \
		vmagent/vmagent --timeout=$(TIMEOUT) > /dev/null
	@echo " ✓ VMAgent operational"
	@echo "Waiting for VMAlert to become operational..."
	@$(KUBECTL) -n monitoring wait --for=jsonpath='{.status.updateStatus}'=operational \
		vmalert/vmalert --timeout=$(TIMEOUT) > /dev/null
	@echo " ✓ VMAlert operational"

# ──────────────────────────────────────────────
# Destroy (reverse order)
# ──────────────────────────────────────────────

destroy: destroy-agents destroy-base destroy-operator ## Tear down everything

destroy-agents: ## Remove VMAgent and VMAlert
	@$(KUBECTL) delete vmagent/vmagent vmalert/vmalert -n monitoring --ignore-not-found > /dev/null
	@echo " ✓ VMAgent and VMAlert removed"

destroy-base: ## Remove base resources
	@$(KUBECTL) delete -k base/ --ignore-not-found > /dev/null
	@echo " ✓ Base resources removed"

destroy-operator: ## Uninstall operators via helmfile
	@helmfile --file helmfile.yaml destroy --quiet
	@echo " ✓ Helm releases removed"

# ──────────────────────────────────────────────
# Observe
# ──────────────────────────────────────────────

status: ## Show VM resources and access URLs
	@echo "=== VMCluster ==="
	@$(KUBECTL) -n monitoring get vmcluster
	@echo ""
	@echo "=== VMAgent ==="
	@$(KUBECTL) -n monitoring get vmagent
	@echo ""
	@echo "=== VMAlert ==="
	@$(KUBECTL) -n monitoring get vmalert
	@echo ""
	@echo "=== Pods ==="
	@$(KUBECTL) -n monitoring get pods -o wide
	@echo ""
	@echo "=== Gateway & Routes ==="
	@$(KUBECTL) -n monitoring get httproute
	@echo ""
	@echo "=== Access ==="
	@echo "  vmselect:     http://vmselect.127.0.0.1.nip.io/select/0/vmui/"
	@echo "  VMAlert:      http://vmalert.127.0.0.1.nip.io"
	@echo "  Alertmanager: http://alertmanager.127.0.0.1.nip.io"

# ──────────────────────────────────────────────
# Render (dry-run)
# ──────────────────────────────────────────────

render: ## Render kustomize manifests to stdout
	@$(KUBECTL) kustomize base/

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-20s %s\n", $$1, $$2}'
