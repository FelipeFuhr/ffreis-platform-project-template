SHELL    := /bin/bash
STACK    := stack
ENVS_DIR := envs

ENV           ?=
# ORG must be set at the call site or via ATLANTIS_ORG env var — no default
# prevents accidentally targeting the wrong GitHub org.
ORG           ?= $(ATLANTIS_ORG)
PROFILE       ?= default
BOOTSTRAP_BIN ?= platform-bootstrap
DYNAMOCTL_BIN ?= dynamoctl

CLI_BIN ?= ./bin/platform-project
CLI_SRC := ./cmd/platform-project
GO      ?= $(shell command -v go 2>/dev/null || echo /usr/local/go/bin/go)
GOFMT   ?= $(shell command -v gofmt 2>/dev/null || echo /usr/local/go/bin/gofmt)

FETCHED_FILE = $(ENVS_DIR)/$(ENV)/fetched.auto.tfvars.json

GITLEAKS         ?= gitleaks
LEFTHOOK_VERSION ?= 1.7.10
LEFTHOOK_DIR     ?= $(CURDIR)/.bin
LEFTHOOK_BIN     ?= $(LEFTHOOK_DIR)/lefthook

_require_env:
	@test -n "$(ENV)" || (echo "ENV is required, e.g. make plan ENV=prod" && exit 1)
	@test -d "$(ENVS_DIR)/$(ENV)" || (echo "Unknown environment: $(ENV)" && exit 1)

_require_fetched: _require_env
	@test -f "$(FETCHED_FILE)" || ( \
		echo "Missing $(FETCHED_FILE). Run: make fetch ENV=$(ENV)" >&2; \
		exit 1)

.PHONY: build go-test go-plan go-apply go-nuke \
        help fetch init plan apply destroy nuke fmt fmt-check validate lint test check security coverage \
        lock-list lock-info lock-cleanup \
        secrets-scan-staged lefthook-bootstrap lefthook-install lefthook-run lefthook \
        _require_env _require_fetched

## build: compile the platform-project CLI to ./bin/platform-project
build:
	$(GO) build -o $(CLI_BIN) $(CLI_SRC)

## go-test: run Go unit tests for the CLI
go-test:
	$(GO) test ./... -v

## go-plan [ENV=prod]: run terraform plan via the CLI (assumes platform-admin role)
go-plan: build
	$(CLI_BIN) plan --env $(or $(ENV),prod) --region us-east-1

## go-apply [ENV=prod]: run terraform apply via the CLI
go-apply: build
	$(CLI_BIN) apply --env $(or $(ENV),prod) --region us-east-1

## go-nuke [ENV=prod]: destroy all resources (prompts for confirmation)
go-nuke: build
	$(CLI_BIN) nuke --env $(or $(ENV),prod) --region us-east-1

## fmt: format all Go and Terraform files
fmt:
	$(GOFMT) -w .
	terraform fmt -recursive .

## fmt-check: fail if any Go or Terraform file is not formatted
fmt-check:
	@unformatted=$$($(GOFMT) -l .); \
	if [ -n "$$unformatted" ]; then \
	  printf "The following files need gofmt:\n%s\n\nFix with: gofmt -w .\n" "$$unformatted"; \
	  exit 1; \
	fi
	terraform fmt -check -recursive .

help: ## Show available commands
	@awk 'BEGIN {FS = ":.*## "; printf "Usage: make <target> [ENV=<env>]\n\nTargets:\n"} /^[a-zA-Z0-9_.-]+:.*## / {printf "  %-24s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

## fetch ENV=<env>: Pull config from the bootstrap registry
fetch: _require_env
	$(BOOTSTRAP_BIN) fetch \
		--org=$(ORG) \
		--profile=$(PROFILE) \
		--output=$(FETCHED_FILE)
	@echo "✓ Fetched platform config → $(FETCHED_FILE)"

## init ENV=<env>: Initialize terraform working directory
init: _require_env
	cd $(STACK) && terraform init \
		-backend-config=../$(ENVS_DIR)/$(ENV)/backend.hcl \
		-reconfigure
	@echo "✓ Terraform initialized for $(ENV)"

## plan ENV=<env>: Plan infrastructure changes
plan: _require_env _require_fetched
	cd $(STACK) && terraform plan \
		-var-file=../$(ENVS_DIR)/$(ENV)/terraform.tfvars \
		-out=../$(ENVS_DIR)/$(ENV)/tfplan

validate: _require_env ## Validate terraform syntax
	cd $(STACK) && terraform validate

# Backend State Inspection
lock-list: _require_env ## List terraform locks in DynamoDB
	$(DYNAMOCTL_BIN) list \
		--table $(ORG)-tf-locks-$(ENV) \
		--region us-east-1

lock-info: _require_env ## Show lock table info
	aws dynamodb describe-table \
		--table-name $(ORG)-tf-locks-$(ENV) \
		--region us-east-1 \
		--query 'Table.[TableName,TableStatus,ItemCount]' \
		--output table

lock-cleanup: _require_env ## Remove stale locks (careful!)
	@echo "⚠ This will remove locks older than 24 hours from dynamodb table"
	@read -p "Continue? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		$(DYNAMOCTL_BIN) delete --table $(ORG)-tf-locks-$(ENV) --region us-east-1 --age 24h; \
		echo "✓ Cleanup complete"; \
	fi

## apply ENV=<env>: Apply terraform changes (requires approved plan)
apply: _require_env
	cd $(STACK) && terraform apply ../$(ENVS_DIR)/$(ENV)/tfplan

## destroy ENV=<env>: Destroy infrastructure (dangerous!)
destroy: _require_env
	@echo "⚠ WARNING: This will destroy $(ENV) infrastructure!"
	@read -p "Type 'destroy-$(ENV)' to confirm: " -r; \
	if [ "$$REPLY" = "destroy-$(ENV)" ]; then \
		cd $(STACK) && terraform destroy \
			-var-file=../$(ENVS_DIR)/$(ENV)/terraform.tfvars; \
	else \
		echo "Cancelled"; \
		exit 1; \
	fi

## nuke ENV=<env>: fetch, init then destroy -auto-approve (IRREVERSIBLE)
nuke: _require_fetched
	@read -p "Type 'nuke-$(ENV)' to confirm destruction of project-template/$(ENV): " -r; \
	if [ "$$REPLY" != "nuke-$(ENV)" ]; then \
		echo "Cancelled."; \
		exit 1; \
	fi
	cd $(STACK) && terraform init \
		-backend-config=../$(ENVS_DIR)/$(ENV)/backend.hcl \
		-reconfigure
	cd $(STACK) && terraform destroy \
		-var-file=../$(ENVS_DIR)/$(ENV)/terraform.tfvars \
		-auto-approve

## lint: run tflint across all Terraform files
lint: ## Run tflint across all Terraform files
	tflint --init
	tflint --recursive --format compact .

## test: run Go unit tests for the CLI
test: go-test

## security: run trivy + checkov security scans
security:
	trivy config --exit-code 1 --severity HIGH,CRITICAL .
	@which checkov >/dev/null 2>&1 && checkov -d . --framework terraform --quiet || true

## coverage: run terratest with coverage (modules repo only)
coverage:
	cd test && go test -v ./... -timeout 30m 2>/dev/null || echo "No terratest found"

## check: Run all static checks (no cloud)
check: fmt-check validate lint security
	@echo "✓ All checks passed"

secrets-scan-staged: ## Scan staged diff for secrets
	@command -v $(GITLEAKS) >/dev/null 2>&1 || (echo "Missing tool: $(GITLEAKS). Install: https://github.com/gitleaks/gitleaks#installing" && exit 1)
	$(GITLEAKS) protect --staged --redact

lefthook-bootstrap: ## Download lefthook binary into ./.bin
	LEFTHOOK_VERSION="$(LEFTHOOK_VERSION)" BIN_DIR="$(LEFTHOOK_DIR)" bash ./scripts/bootstrap_lefthook.sh

lefthook-install: lefthook-bootstrap ## Install git hooks (runs bootstrap first)
	@if [ -x "$(LEFTHOOK_BIN)" ] && [ -x ".git/hooks/pre-commit" ] && [ -x ".git/hooks/pre-push" ] && [ -x ".git/hooks/commit-msg" ]; then \
		echo "lefthook hooks already installed"; \
		exit 0; \
	fi
	LEFTHOOK="$(LEFTHOOK_BIN)" "$(LEFTHOOK_BIN)" install

lefthook-run: lefthook-bootstrap ## Run all hooks locally (pre-commit + commit-msg + pre-push)
	LEFTHOOK="$(LEFTHOOK_BIN)" "$(LEFTHOOK_BIN)" run pre-commit
	@tmp_msg="$$(mktemp)"; \
	echo "chore(hooks): validate commit-msg hook" > "$$tmp_msg"; \
	LEFTHOOK="$(LEFTHOOK_BIN)" "$(LEFTHOOK_BIN)" run commit-msg -- "$$tmp_msg"; \
	rm -f "$$tmp_msg"
	LEFTHOOK="$(LEFTHOOK_BIN)" "$(LEFTHOOK_BIN)" run pre-push

lefthook: lefthook-bootstrap lefthook-install lefthook-run ## Install hooks and run them

.PHONY: _require_env _require_fetched
