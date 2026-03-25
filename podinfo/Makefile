KUBECONFIG ?= ../kubeconfig
CONTEXT    ?= kind-playground
KUBECTL    := kubectl --context $(CONTEXT)
TIMEOUT    := 120s

export KUBECONFIG

.PHONY: deploy destroy status help

deploy: ## Deploy podinfo (25 replicas across 3 AZs)
	@helmfile --file helmfile.yaml sync --quiet
	@echo " ✓ Helmfile sync complete"
	@$(KUBECTL) -n podinfo rollout status deployment/podinfo --timeout=$(TIMEOUT) > /dev/null
	@echo " ✓ podinfo ready"
	@echo "   Access: http://podinfo.127.0.0.1.nip.io"

destroy: ## Remove podinfo
	@helmfile --file helmfile.yaml destroy --quiet
	@echo " ✓ podinfo removed"

status: ## Show podinfo pods and their AZ distribution
	@echo "=== Deployment ==="
	@$(KUBECTL) -n podinfo get deployment podinfo
	@echo ""
	@echo "=== Pods by Zone ==="
	@$(KUBECTL) -n podinfo get pods -o wide \
		--label-columns topology.kubernetes.io/zone 2>/dev/null || \
		$(KUBECTL) -n podinfo get pods -o wide
	@echo ""
	@echo "=== ServiceMonitor ==="
	@$(KUBECTL) -n podinfo get servicemonitor 2>/dev/null || echo "  (no ServiceMonitor found)"
	@echo ""
	@echo "=== Access ==="
	@echo "  podinfo UI: http://podinfo.127.0.0.1.nip.io"

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-12s %s\n", $$1, $$2}'
