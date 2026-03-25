KUBECONFIG ?= ../kubeconfig
CONTEXT    ?= kind-playground
KUBECTL    := kubectl --context $(CONTEXT)
TIMEOUT    := 120s

export KUBECONFIG

.PHONY: deploy destroy status help

deploy: ## Deploy Beyla eBPF network observability DaemonSet
	@helmfile --file helmfile.yaml sync --quiet
	@echo " ✓ Helmfile sync complete"
	@$(KUBECTL) -n beyla rollout status daemonset/beyla --timeout=$(TIMEOUT) > /dev/null
	@echo " ✓ Beyla ready (running on all nodes)"

destroy: ## Remove Beyla
	@helmfile --file helmfile.yaml destroy --quiet
	@echo " ✓ Beyla removed"

status: ## Show Beyla DaemonSet status and node coverage
	@echo "=== DaemonSet ==="
	@$(KUBECTL) -n beyla get daemonset beyla
	@echo ""
	@echo "=== Pods by Node ==="
	@$(KUBECTL) -n beyla get pods -o wide
	@echo ""
	@echo "=== ServiceMonitor ==="
	@$(KUBECTL) -n beyla get servicemonitor 2>/dev/null || echo "  (no ServiceMonitor found)"

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-12s %s\n", $$1, $$2}'
