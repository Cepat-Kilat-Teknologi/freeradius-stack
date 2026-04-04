.PHONY: help build push build-multiarch push-multiarch docker-up docker-down k8s-apply k8s-delete helm-install helm-uninstall

# Configuration
IMAGE_NAME ?= freeradius
IMAGE_TAG ?= latest
REGISTRY ?=

# Full image name
ifdef REGISTRY
FULL_IMAGE = $(REGISTRY)/$(IMAGE_NAME):$(IMAGE_TAG)
else
FULL_IMAGE = $(IMAGE_NAME):$(IMAGE_TAG)
endif

help:
	@echo "FreeRADIUS Stack"
	@echo "================"
	@echo ""
	@echo "Image Build:"
	@echo "  make build                    - Build Docker image"
	@echo "  make build TAG=v1.0.0         - Build with specific tag"
	@echo "  make push                     - Push to registry"
	@echo "  make push REGISTRY=ghcr.io/user - Push to specific registry"
	@echo "  make build-multiarch          - Build multi-arch image (amd64+arm64)"
	@echo "  make push-multiarch           - Build and push multi-arch image"
	@echo ""
	@echo "Docker Compose (examples/docker/):"
	@echo "  make docker-up                - Start with Docker Compose"
	@echo "  make docker-down              - Stop Docker Compose"
	@echo "  make docker-logs              - View logs"
	@echo ""
	@echo "Kubernetes (examples/kubernetes/):"
	@echo "  make k8s-apply                - Apply manifests"
	@echo "  make k8s-delete               - Delete resources"
	@echo ""
	@echo "Helm (examples/helm/):"
	@echo "  make helm-install             - Install chart"
	@echo "  make helm-upgrade             - Upgrade release"
	@echo "  make helm-uninstall           - Uninstall release"
	@echo "  make helm-template            - Render templates"
	@echo ""
	@echo "For detailed usage, see examples/*/README.md"

# ==================== Image Build ====================

build:
	docker build -t $(FULL_IMAGE) .
	@echo "Built: $(FULL_IMAGE)"

build-no-cache:
	docker build --no-cache -t $(FULL_IMAGE) .

push: build
	docker push $(FULL_IMAGE)
	@echo "Pushed: $(FULL_IMAGE)"

build-multiarch:
	docker buildx build --platform linux/amd64,linux/arm64 -t $(FULL_IMAGE) .
	@echo "Built multiarch: $(FULL_IMAGE)"

push-multiarch:
	docker buildx build --platform linux/amd64,linux/arm64 -t $(FULL_IMAGE) --push .
	@echo "Pushed multiarch: $(FULL_IMAGE)"

tag:
	docker tag $(IMAGE_NAME):$(IMAGE_TAG) $(REGISTRY)/$(IMAGE_NAME):$(IMAGE_TAG)

# ==================== Docker Compose ====================

docker-up:
	cd examples/docker && $(MAKE) up

docker-down:
	cd examples/docker && $(MAKE) down

docker-logs:
	cd examples/docker && $(MAKE) logs

docker-clean:
	cd examples/docker && $(MAKE) clean

# ==================== Kubernetes ====================

k8s-apply:
	kubectl apply -k examples/kubernetes/

k8s-delete:
	kubectl delete -k examples/kubernetes/

k8s-status:
	kubectl -n freeradius get pods,svc,pvc

k8s-logs:
	kubectl -n freeradius logs -l app.kubernetes.io/name=freeradius -f

# ==================== Helm ====================

HELM_RELEASE ?= freeradius
HELM_NAMESPACE ?= freeradius

helm-install:
	helm install $(HELM_RELEASE) examples/helm/freeradius \
		--namespace $(HELM_NAMESPACE) \
		--create-namespace

helm-upgrade:
	helm upgrade $(HELM_RELEASE) examples/helm/freeradius \
		--namespace $(HELM_NAMESPACE)

helm-uninstall:
	helm uninstall $(HELM_RELEASE) --namespace $(HELM_NAMESPACE)

helm-template:
	helm template $(HELM_RELEASE) examples/helm/freeradius

helm-lint:
	helm lint examples/helm/freeradius

helm-status:
	helm status $(HELM_RELEASE) --namespace $(HELM_NAMESPACE)

# ==================== Development ====================

dev:
	cd examples/docker && cp .env.example .env
	@echo "Edit examples/docker/.env then run: make docker-up"

test:
	@echo "Running tests..."
	cd examples/docker && $(MAKE) test-auth
