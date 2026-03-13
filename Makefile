CLUSTER_NAME := playground
KIND_CONFIG  := kind-config.yaml
KUBECTL      := kubectl --context kind-$(CLUSTER_NAME)

# inotify limits required for multi-node Kind clusters
INOTIFY_MAX_USER_WATCHES   := 524288
INOTIFY_MAX_USER_INSTANCES := 512

.PHONY: create delete status kubeconfig preflight help

create: preflight ## Create the Kind cluster and install base components
	@kind create cluster --name $(CLUSTER_NAME) --config $(KIND_CONFIG)
	@echo " ✓ Spreading CoreDNS across zones"
	@$(KUBECTL) patch deployment coredns -n kube-system --type merge -p '{ \
		"spec": { "template": { "spec": { "topologySpreadConstraints": [ \
			{ "maxSkew": 1, "topologyKey": "topology.kubernetes.io/zone", \
			  "whenUnsatisfiable": "DoNotSchedule", \
			  "labelSelector": { "matchLabels": { "k8s-app": "kube-dns" } } } \
		] } } } }' > /dev/null
	@$(KUBECTL) rollout status deployment/coredns -n kube-system --timeout=60s > /dev/null
	@echo " ✓ CoreDNS ready"
	@$(MAKE) --no-print-directory -C envoy-gateway deploy

delete: ## Delete the Kind cluster
	@kind delete cluster --name $(CLUSTER_NAME)

status: ## Show cluster info and node topology labels
	@$(KUBECTL) cluster-info
	@echo ""
	@$(KUBECTL) get nodes -L topology.kubernetes.io/zone

kubeconfig: ## Print the kubeconfig for the cluster
	@kind get kubeconfig --name $(CLUSTER_NAME)

preflight: ## Detect container runtime and ensure inotify limits are set
	@if colima status >/dev/null 2>&1; then \
		echo "Detected runtime: Colima"; \
		current_watches=$$(colima ssh -- sysctl -n fs.inotify.max_user_watches 2>/dev/null); \
		current_instances=$$(colima ssh -- sysctl -n fs.inotify.max_user_instances 2>/dev/null); \
		if [ "$$current_watches" -lt $(INOTIFY_MAX_USER_WATCHES) ] 2>/dev/null; then \
			echo "Setting fs.inotify.max_user_watches=$(INOTIFY_MAX_USER_WATCHES) (was $$current_watches)"; \
			colima ssh -- sudo sysctl -w fs.inotify.max_user_watches=$(INOTIFY_MAX_USER_WATCHES); \
		else \
			echo "fs.inotify.max_user_watches=$$current_watches (ok)"; \
		fi; \
		if [ "$$current_instances" -lt $(INOTIFY_MAX_USER_INSTANCES) ] 2>/dev/null; then \
			echo "Setting fs.inotify.max_user_instances=$(INOTIFY_MAX_USER_INSTANCES) (was $$current_instances)"; \
			colima ssh -- sudo sysctl -w fs.inotify.max_user_instances=$(INOTIFY_MAX_USER_INSTANCES); \
		else \
			echo "fs.inotify.max_user_instances=$$current_instances (ok)"; \
		fi; \
	elif docker info --format '{{.Name}}' 2>/dev/null | grep -qi desktop; then \
		echo "Detected runtime: Docker Desktop"; \
		current_watches=$$(docker run --rm --privileged alpine sysctl -n fs.inotify.max_user_watches 2>/dev/null); \
		current_instances=$$(docker run --rm --privileged alpine sysctl -n fs.inotify.max_user_instances 2>/dev/null); \
		if [ "$$current_watches" -lt $(INOTIFY_MAX_USER_WATCHES) ] 2>/dev/null; then \
			echo "Setting fs.inotify.max_user_watches=$(INOTIFY_MAX_USER_WATCHES) (was $$current_watches)"; \
			docker run --rm --privileged alpine sysctl -w fs.inotify.max_user_watches=$(INOTIFY_MAX_USER_WATCHES); \
		else \
			echo "fs.inotify.max_user_watches=$$current_watches (ok)"; \
		fi; \
		if [ "$$current_instances" -lt $(INOTIFY_MAX_USER_INSTANCES) ] 2>/dev/null; then \
			echo "Setting fs.inotify.max_user_instances=$(INOTIFY_MAX_USER_INSTANCES) (was $$current_instances)"; \
			docker run --rm --privileged alpine sysctl -w fs.inotify.max_user_instances=$(INOTIFY_MAX_USER_INSTANCES); \
		else \
			echo "fs.inotify.max_user_instances=$$current_instances (ok)"; \
		fi; \
	else \
		echo "ERROR: Could not detect Colima or Docker Desktop"; \
		exit 1; \
	fi

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-12s %s\n", $$1, $$2}'
