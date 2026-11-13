# Local entry points. Every target here runs the same checks as CI, without
# touching AWS. Run `make check` before opening a pull request.

SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

TF_ENVS := terraform/envs/staging terraform/envs/prod

.PHONY: help
help: ## List available targets
	@awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z_-]+:.*## / {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

.PHONY: fmt
fmt: ## Format Terraform in place
	terraform fmt -recursive terraform

.PHONY: fmt-check
fmt-check: ## Fail if Terraform is not formatted
	terraform fmt -check -recursive terraform

.PHONY: validate
validate: ## terraform init -backend=false and validate each environment root
	@for env in $(TF_ENVS); do \
	  echo "==> validate $$env"; \
	  (cd $$env && terraform init -backend=false -input=false -no-color >/dev/null && terraform validate -no-color) || exit 1; \
	done

.PHONY: lint
lint: ## Run tflint (terraform and aws rulesets) recursively
	cd terraform && tflint --init && tflint --recursive --config "$(CURDIR)/.tflint.hcl"

.PHONY: security
security: ## Run Checkov against the Terraform tree (hard fail)
	checkov -d terraform --framework terraform --config-file .checkov.yaml

.PHONY: gitops
gitops: ## Lint, render, schema-check and policy-test the GitOps tree
	./scripts/validate-gitops.sh

.PHONY: lock
lock: ## Regenerate provider lock files for linux_amd64 and darwin_arm64
	@for env in $(TF_ENVS); do \
	  (cd $$env && terraform init -backend=false -input=false -no-color >/dev/null && \
	    terraform providers lock -platform=linux_amd64 -platform=darwin_arm64); \
	done

.PHONY: check
check: fmt-check validate lint security gitops ## Run every local check

.PHONY: clean
clean: ## Remove local Terraform state caches and rendered output
	@find terraform -type d -name .terraform -prune -exec rm -rf {} +
	@rm -rf .rendered
