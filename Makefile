SHELL := /bin/bash

WEBSITE_COMPILER ?= ./website-compiler/cmd/build-static
WEBSITE_COMPILER_CLI ?= ./website-compiler/cmd/website-compiler
OUT_CHECK ?= /tmp/website-template-dist-check
GITLEAKS ?= gitleaks
LEFTHOOK_VERSION ?= 2.1.4
LEFTHOOK_DIR ?= $(CURDIR)/.bin
LEFTHOOK_BIN ?= $(LEFTHOOK_DIR)/lefthook

.PHONY: help format-check js-syntax sanity-check site-data-check asset-usage-check template-compile-check
.PHONY: build-static-check build-inline-check check secrets-scan-staged lefthook-bootstrap lefthook-install lefthook-run lefthook

help: ## Show available website checks
	@awk 'BEGIN {FS = ":.*## "; printf "Usage: make <target>\n\nTargets:\n"} /^[a-zA-Z0-9_.-]+:.*## / {printf "  %-24s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

format-check: ## Prettier check for CSS/JS under src/assets/
	npx --yes prettier@3.3.3 --check "src/assets/**/*.css" "src/assets/**/*.js"

js-syntax: ## JavaScript syntax check for all assets JS files
	@set -euo pipefail; \
	while IFS= read -r file; do \
		node --check "$$file"; \
	done < <(find src/assets -type f -name '*.js' | sort)

sanity-check: ## Run compiler sanity checks when supported by the configured compiler
	@set -euo pipefail; \
	SITE_ROOT="$$(pwd)"; \
	CLI="$(WEBSITE_COMPILER_CLI)"; \
	if [[ -x "$$CLI" && ! -d "$$CLI" ]]; then \
		"$$CLI" validate-sanity -website-root "$$SITE_ROOT"; \
	else \
		MOD="$$(cd "$$(dirname "$$CLI")/.." && pwd)"; \
		go -C "$$MOD" run ./cmd/website-compiler validate-sanity -website-root "$$SITE_ROOT"; \
	fi

site-data-check: ## Validate site data against the local site data contract
	@set -euo pipefail; \
	SITE_ROOT="$$(pwd)"; \
	CLI="$(WEBSITE_COMPILER_CLI)"; \
	if [[ -x "$$CLI" && ! -d "$$CLI" ]]; then \
		"$$CLI" validate-site-data -website-root "$$SITE_ROOT"; \
	else \
		MOD="$$(cd "$$(dirname "$$CLI")/.." && pwd)"; \
		go -C "$$MOD" run ./cmd/website-compiler validate-site-data -website-root "$$SITE_ROOT"; \
	fi

asset-usage-check: ## Validate that all local CSS/JS assets are reachable from rendered pages
	@set -euo pipefail; \
	SITE_ROOT="$$(pwd)"; \
	CLI="$(WEBSITE_COMPILER_CLI)"; \
	if [[ -x "$$CLI" && ! -d "$$CLI" ]]; then \
		"$$CLI" validate-assets -website-root "$$SITE_ROOT"; \
	else \
		MOD="$$(cd "$$(dirname "$$CLI")/.." && pwd)"; \
		go -C "$$MOD" run ./cmd/website-compiler validate-assets -website-root "$$SITE_ROOT"; \
	fi

build-static-check: ## Build output with copied assets and verify index exists
	@set -euo pipefail; \
	SITE_ROOT="$$(pwd)"; \
	OUT="/tmp/website-template-dist"; \
	rm -rf "$$OUT"; \
	COMPILER="$(WEBSITE_COMPILER)"; \
	if [[ -x "$$COMPILER" && ! -d "$$COMPILER" ]]; then \
		"$$COMPILER" -website-root "$$SITE_ROOT" -out "$$OUT"; \
	else \
		MOD="$$(cd "$$(dirname "$$COMPILER")/.." && pwd)"; \
		go -C "$$MOD" run ./cmd/build-static -website-root "$$SITE_ROOT" -out "$$OUT"; \
	fi; \
	test -f "$$OUT/index.html"

build-inline-check: ## Build output with inline assets and verify index exists
	@set -euo pipefail; \
	SITE_ROOT="$$(pwd)"; \
	OUT="/tmp/website-template-dist-inline"; \
	rm -rf "$$OUT"; \
	COMPILER="$(WEBSITE_COMPILER)"; \
	if [[ -x "$$COMPILER" && ! -d "$$COMPILER" ]]; then \
		"$$COMPILER" -website-root "$$SITE_ROOT" -out "$$OUT" -inline-assets; \
	else \
		MOD="$$(cd "$$(dirname "$$COMPILER")/.." && pwd)"; \
		go -C "$$MOD" run ./cmd/build-static -website-root "$$SITE_ROOT" -out "$$OUT" -inline-assets; \
	fi; \
	test -f "$$OUT/index.html"

template-compile-check: ## Build and verify that template pages match compiled pages
	@set -euo pipefail; \
	SITE_ROOT="$$(pwd)"; \
	rm -rf "$(OUT_CHECK)"; \
	COMPILER="$(WEBSITE_COMPILER)"; \
	if [[ -x "$$COMPILER" && ! -d "$$COMPILER" ]]; then \
		"$$COMPILER" -website-root "$$SITE_ROOT" -out "$(OUT_CHECK)"; \
	else \
		MOD="$$(cd "$$(dirname "$$COMPILER")/.." && pwd)"; \
		go -C "$$MOD" run ./cmd/build-static -website-root "$$SITE_ROOT" -out "$(OUT_CHECK)"; \
	fi; \
	find src/templates/pages -type f -name '*.gohtml' -printf '%f\n' | sed 's/\.gohtml$$//' | sort > /tmp/template-pages.txt; \
	find "$(OUT_CHECK)" -maxdepth 1 -type f -name '*.html' -printf '%f\n' | sed 's/\.html$$//' | sort > /tmp/compiled-pages.txt; \
	diff -u /tmp/template-pages.txt /tmp/compiled-pages.txt

check: ## Run all website quality checks
	$(MAKE) format-check
	$(MAKE) js-syntax
	$(MAKE) sanity-check
	$(MAKE) site-data-check
	$(MAKE) asset-usage-check
	$(MAKE) template-compile-check
	$(MAKE) build-static-check
	$(MAKE) build-inline-check

secrets-scan-staged: ## Scan staged diff for secrets
	@command -v $(GITLEAKS) >/dev/null 2>&1 || (echo "Missing tool: $(GITLEAKS). Install: https://github.com/gitleaks/gitleaks#installing" && exit 1)
	$(GITLEAKS) protect --staged --redact

lefthook-bootstrap: ## Download lefthook binary into ./.bin
	go install github.com/evilmartians/lefthook/v2@v$(LEFTHOOK_VERSION)
	@mkdir -p "$(LEFTHOOK_DIR)"
	@cp "$$(go env GOPATH)/bin/lefthook" "$(LEFTHOOK_BIN)"

lefthook-install: lefthook-bootstrap ## Install git hooks
	LEFTHOOK="$(LEFTHOOK_BIN)" "$(LEFTHOOK_BIN)" install

lefthook-run: lefthook-bootstrap ## Run all CI checks locally
	LEFTHOOK="$(LEFTHOOK_BIN)" "$(LEFTHOOK_BIN)" run ci

lefthook: lefthook-bootstrap lefthook-install lefthook-run ## Install hooks and run them

install-act: ## Download pinned act binary into .bin/
	@mkdir -p scripts
	@curl -fsSL "$(PLATFORM_STANDARDS_RAW)/$(PLATFORM_STANDARDS_SHA)/scripts/install_act.sh" \
		-o scripts/install_act.sh && chmod +x scripts/install_act.sh
	@bash ./scripts/install_act.sh

ci-local: ## Run workflows locally via act (GH Actions quota fallback). Args via ARGS=...
	@mkdir -p scripts
	@curl -fsSL "$(PLATFORM_STANDARDS_RAW)/$(PLATFORM_STANDARDS_SHA)/scripts/run-ci-local.sh" \
		-o scripts/run-ci-local.sh && chmod +x scripts/run-ci-local.sh
	@PATH="$(CURDIR)/.bin:$(PATH)" bash ./scripts/run-ci-local.sh $(ARGS)
