KUBECONFIG ?= ../kubeconfig
CONTEXT    ?= kind-playground
KUBECTL    := kubectl --context $(CONTEXT)
TIMEOUT    := 180s

ZONES := eu-west-1a eu-west-1b eu-west-1c

export KUBECONFIG

.PHONY: all deploy deploy-operator deploy-base deploy-clusters deploy-agents \
        destroy destroy-agents destroy-clusters destroy-base destroy-operator \
        status render help

all: deploy ## Full deploy: operator + base + agents

# ──────────────────────────────────────────────
# Deploy
# ──────────────────────────────────────────────

deploy: deploy-operator deploy-base deploy-clusters deploy-agents ## Deploy everything

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

deploy-base: ## Apply base resources (federated vmselect, VMAlert, alertmanager, gateway)
	@$(KUBECTL) apply -k base/ > /dev/null
	@echo " ✓ Base resources applied"
	@echo "Waiting for alertmanager..."
	@$(KUBECTL) -n monitoring rollout status statefulset/alertmanager-kube-prometheus-stack-alertmanager --timeout=$(TIMEOUT) > /dev/null
	@echo " ✓ Alertmanager ready"

deploy-clusters: ## Apply per-AZ VMCluster overlays
	@for zone in $(ZONES); do \
		$(KUBECTL) apply -k clusters/overlays/$$zone/ > /dev/null; \
		echo " ✓ VMCluster $$zone applied"; \
	done
	@echo "Waiting for VMClusters to become operational..."
	@for zone in $(ZONES); do \
		$(KUBECTL) -n monitoring wait --for=jsonpath='{.status.updateStatus}'=operational \
			vmcluster/vm-$$zone-vmcluster --timeout=$(TIMEOUT) > /dev/null; \
		echo " ✓ VMCluster $$zone operational"; \
	done
	@echo "Waiting for federated vmselect..."
	@$(KUBECTL) -n monitoring rollout status deployment/vmselect-federated --timeout=$(TIMEOUT) > /dev/null
	@echo " ✓ Federated vmselect ready"

deploy-agents: ## Apply per-AZ VMAgent overlays
	@for zone in $(ZONES); do \
		short=$$(echo $$zone | sed 's/eu-west-1//'); \
		$(KUBECTL) apply -k agents/overlays/$$zone/ > /dev/null; \
		echo " ✓ VMAgent zone-$$short applied"; \
	done
	@echo "Waiting for VMAgents to become operational..."
	@for zone in $(ZONES); do \
		short=$$(echo $$zone | sed 's/eu-west-1//'); \
		$(KUBECTL) -n monitoring wait --for=jsonpath='{.status.updateStatus}'=operational \
			vmagent/zone-$$short-vmagent --timeout=$(TIMEOUT) > /dev/null; \
		echo " ✓ VMAgent zone-$$short operational"; \
	done
	@echo "Waiting for VMAlert to become operational..."
	@$(KUBECTL) -n monitoring wait --for=jsonpath='{.status.updateStatus}'=operational \
		vmalert/vmalert --timeout=$(TIMEOUT) > /dev/null
	@echo " ✓ VMAlert operational"

# ──────────────────────────────────────────────
# Destroy (reverse order)
# ──────────────────────────────────────────────

destroy: destroy-agents destroy-clusters destroy-base destroy-operator ## Tear down everything

destroy-agents: ## Remove per-AZ VMAgents
	@for zone in $(ZONES); do \
		short=$$(echo $$zone | sed 's/eu-west-1//'); \
		$(KUBECTL) delete -k agents/overlays/$$zone/ --ignore-not-found > /dev/null; \
		echo " ✓ VMAgent zone-$$short removed"; \
	done

destroy-clusters: ## Remove per-AZ VMClusters
	@for zone in $(ZONES); do \
		short=$$(echo $$zone | sed 's/eu-west-1//'); \
		$(KUBECTL) delete -k clusters/overlays/$$zone/ --ignore-not-found > /dev/null; \
		echo " ✓ VMCluster $$zone removed"; \
	done

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
	@echo "=== VMClusters ==="
	@$(KUBECTL) -n monitoring get vmcluster
	@echo ""
	@echo "=== VMAgents ==="
	@$(KUBECTL) -n monitoring get vmagent
	@echo ""
	@echo "=== VMAlert ==="
	@$(KUBECTL) -n monitoring get vmalert
	@echo ""
	@echo "=== Pods ==="
	@$(KUBECTL) -n monitoring get pods -o wide
	@echo ""
	@echo "=== Gateway & Routes ==="
	@$(KUBECTL) -n monitoring get gateway,httproute
	@echo ""
	@echo "=== Access ==="
	@echo "  Federated vmselect: http://vmselect.127.0.0.1.nip.io/select/0/vmui/"
	@echo "  VMAlert:            http://vmalert.127.0.0.1.nip.io"
	@echo "  Alertmanager:       http://alertmanager.127.0.0.1.nip.io"
	@for zone in $(ZONES); do \
		short=$$(echo $$zone | sed 's/.*-//'); \
		echo "  vmselect ($$zone):  http://vmselect-$$short.127.0.0.1.nip.io/select/0/vmui/"; \
	done

# ──────────────────────────────────────────────
# Render (dry-run)
# ──────────────────────────────────────────────

render: ## Render all kustomize manifests to stdout
	@echo "--- base ---"
	@$(KUBECTL) kustomize base/
	@for zone in $(ZONES); do \
		echo ""; \
		echo "--- cluster: $$zone ---"; \
		$(KUBECTL) kustomize clusters/overlays/$$zone/; \
	done
	@for zone in $(ZONES); do \
		echo ""; \
		short=$$(echo $$zone | sed 's/eu-west-1//'); \
		echo "--- agent: zone-$$short ---"; \
		$(KUBECTL) kustomize agents/overlays/$$zone/; \
	done

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-20s %s\n", $$1, $$2}'
