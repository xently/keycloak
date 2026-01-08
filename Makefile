.PHONY: help build-images build-and-push-images k8s k8s-delete k8s-production k8s-production-delete

# Define a consistent name for your multi-arch builder
BUILDER_NAME ?= xently
VERSION ?= 26.3.1

help: ## Display this help message.
	@echo "Please use \`make <target>\` where <target> is one of:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; \
	{printf "\033[36m%-40s\033[0m %s\n", $$1, $$2}'

update-hosts: ## Update hosts file.
	@echo "\033[0;33mUpdating hosts file if necessary...\e[0m"
	@if ! grep -q -F "keycloak.keycloak.svc.cluster.local" /etc/hosts; then\
	  echo "127.0.0.1	keycloak.keycloak.svc.cluster.local" | sudo tee -a /etc/hosts > /dev/null && echo "\033[0;32m✅ hosts file updated.\e[0m" || echo "\033[0;31m❌ Failed to update hosts file.\e[0m";\
	else\
	  echo "\033[0;32m✅ Entry already exists. No changes made.\e[0m";\
	fi

drop-release: ## Delete a release tag and push to GitHub.
	git tag --delete $(VERSION)
	git push --delete origin $(VERSION)

release: ## Tag a new release and push to GitHub.
	git tag -sa $(VERSION) -m "Version $(VERSION)"
	git push --tags

re-release: drop-release release ## Delete a release and then tag and push the same release tag.

commission-buildx: ## Commission the Docker buildx
	@echo "\033[0;33mCheck if the builder already exists...\e[0m"
	@if ! docker buildx inspect $(BUILDER_NAME) > /dev/null 2>&1; then\
	  echo "\033[0;32mCreating new multi-arch builder: $(BUILDER_NAME)...\e[0m";\
	  docker buildx create --name $(BUILDER_NAME) --use;\
	else\
	  echo "\033[0;32mUsing existing builder: $(BUILDER_NAME)\e[0m";\
	  docker buildx use $(BUILDER_NAME);\
	fi
	@echo "\033[0;33mEnsure the builder is started...\e[0m"
	docker buildx inspect --bootstrap > /dev/null 2>&1

decommission-buildx: ## Decommission the Docker buildx
	docker buildx rm $(BUILDER_NAME)

build-images: commission-buildx ## Build Docker images.
	docker buildx build \
		--build-arg TAG=$(VERSION) \
		--platform linux/amd64,linux/arm64 \
		--tag ghcr.io/xently/keycloak:$(VERSION) .
	$(MAKE) decommission-buildx

build-and-push-images: commission-buildx ## Build and push Docker images.
	docker buildx build \
		--build-arg TAG=$(VERSION) \
		--platform linux/amd64,linux/arm64 \
		--tag ghcr.io/xently/keycloak:$(VERSION) \
		--push .
	$(MAKE) decommission-buildx

k8s: update-hosts ## Start kubernetes development cluster.
	kubectl apply -k ./ops/k8s/overlays/development/

k8s-delete: ## Delete kubernetes development cluster.
	kubectl delete -k ./ops/k8s/overlays/development/

k8s-production: ## Start kubernetes production cluster.
	kubectl apply -k ./ops/k8s/overlays/production/

k8s-production-delete: ## Delete kubernetes production cluster.
	kubectl delete -k ./ops/k8s/overlays/production/
