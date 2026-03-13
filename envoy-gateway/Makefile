KUBECONFIG ?= ../kubeconfig
CONTEXT    ?= kind-playground
KUBECTL    := kubectl --context $(CONTEXT)
TIMEOUT    := 120s

export KUBECONFIG

.PHONY: deploy destroy status help

deploy: ## Install Envoy Gateway and base resources
	@echo " ⏳ Installing Envoy Gateway..."
	@helmfile --file helmfile.yaml sync --quiet > /dev/null
	@$(KUBECTL) -n envoy-gateway-system rollout status deployment/envoy-gateway --timeout=$(TIMEOUT) > /dev/null
	@$(KUBECTL) apply -k base/ > /dev/null
	@echo " ✓ Envoy Gateway ready"

destroy: ## Remove Envoy Gateway
	@$(KUBECTL) delete -k base/ --ignore-not-found > /dev/null
	@helmfile --file helmfile.yaml destroy --quiet > /dev/null
	@echo " ✓ Envoy Gateway removed"

status: ## Show Envoy Gateway status
	@echo "=== Envoy Gateway ==="
	@$(KUBECTL) -n envoy-gateway-system get pods
	@echo ""
	@echo "=== GatewayClass ==="
	@$(KUBECTL) get gatewayclass

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-12s %s\n", $$1, $$2}'
