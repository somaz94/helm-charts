# helm-charts — repo-level automation
#
# Convenience targets for local development, validation, and release prep.
# All chart-targeting targets accept CHART=<name> to limit to one chart.
# Without CHART, targets run against every chart under charts/.

CHARTS_DIR ?= charts
CHART      ?=
LEVEL      ?= patch

SHELL = /usr/bin/env bash -o pipefail
.SHELLFLAGS = -ec

# Auto-discover all charts under charts/
ALL_CHARTS := $(shell find $(CHARTS_DIR) -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null | sort)

# When CHART is set, target only that chart; otherwise target all charts
ifeq ($(CHART),)
TARGET_CHARTS := $(ALL_CHARTS)
else
TARGET_CHARTS := $(CHART)
endif

.PHONY: all
all: lint template ## Default: lint + template all charts.

##@ General

.PHONY: help
help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m [VAR=value ...]\n\nVariables:\n  \033[36mCHART\033[0m   target a single chart (default: all charts under $(CHARTS_DIR)/)\n  \033[36mLEVEL\033[0m   patch | minor | major (used by bump, default: patch)\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

.PHONY: charts
charts: ## List all charts and their current versions.
	@for c in $(ALL_CHARTS); do \
		v=$$(awk '/^version:/ {print $$2}' $(CHARTS_DIR)/$$c/Chart.yaml); \
		printf "  %-30s %s\n" "$$c" "$$v"; \
	done

.PHONY: version
version: ## Show CHART current version. Usage: make version CHART=<name>
	@if [ -z "$(CHART)" ]; then echo "ERROR: CHART is required"; exit 1; fi
	@if [ ! -d "$(CHARTS_DIR)/$(CHART)" ]; then echo "ERROR: chart not found: $(CHARTS_DIR)/$(CHART)"; exit 1; fi
	@awk '/^version:/ {print $$2}' $(CHARTS_DIR)/$(CHART)/Chart.yaml

##@ Development

.PHONY: lint
lint: ## helm lint each chart (CHART=name to limit).
	@for c in $(TARGET_CHARTS); do \
		echo "==> helm lint $$c"; \
		helm lint $(CHARTS_DIR)/$$c; \
	done

.PHONY: ct-lint
ct-lint: ## chart-testing lint (matches CI behavior).
	@command -v ct >/dev/null 2>&1 || { echo "chart-testing required: brew install chart-testing"; exit 1; }
	ct lint --target-branch main --check-version-increment=false

.PHONY: template
template: ## helm template render smoke test (CHART=name to limit).
	@for c in $(TARGET_CHARTS); do \
		echo "==> helm template $$c"; \
		helm template ci $(CHARTS_DIR)/$$c > /dev/null; \
	done

.PHONY: validate
validate: ## kubeconform validation against k8s + CRD schemas (CHART=name to limit).
	@command -v kubeconform >/dev/null 2>&1 || { echo "kubeconform required: brew install kubeconform"; exit 1; }
	@for c in $(TARGET_CHARTS); do \
		echo "==> kubeconform $$c"; \
		helm template ci $(CHARTS_DIR)/$$c | kubeconform \
			-strict \
			-ignore-missing-schemas \
			-schema-location default \
			-schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
			-summary; \
	done

.PHONY: ci
ci: lint ct-lint template validate ## Run the full CI suite locally.

##@ Packaging

.PHONY: package
package: ## helm package each chart into ./.cr-release-packages/ (CHART=name to limit).
	@mkdir -p .cr-release-packages
	@for c in $(TARGET_CHARTS); do \
		echo "==> helm package $$c"; \
		helm package $(CHARTS_DIR)/$$c -d .cr-release-packages; \
	done

.PHONY: clean
clean: ## Remove generated tarballs and helm artifacts.
	rm -rf .cr-release-packages

##@ Release

.PHONY: bump
bump: ## Bump CHART version. Usage: make bump CHART=<name> LEVEL=patch|minor|major
	@if [ -z "$(CHART)" ]; then echo "ERROR: CHART is required (e.g. make bump CHART=nginx-gateway-cr LEVEL=patch)"; exit 1; fi
	@if [ ! -d "$(CHARTS_DIR)/$(CHART)" ]; then echo "ERROR: chart not found: $(CHARTS_DIR)/$(CHART)"; exit 1; fi
	@case "$(LEVEL)" in patch|minor|major) ;; *) echo "ERROR: LEVEL must be patch, minor, or major (got: $(LEVEL))"; exit 1 ;; esac
	@CURRENT=$$(awk '/^version:/ {print $$2}' $(CHARTS_DIR)/$(CHART)/Chart.yaml | tr -d '"'); \
	IFS='.' read -r MAJ MIN PAT <<< "$$CURRENT"; \
	if [[ -z "$$MAJ" || -z "$$MIN" || -z "$$PAT" ]]; then \
		echo "ERROR: cannot parse current version '$$CURRENT' as semver"; exit 1; \
	fi; \
	case "$(LEVEL)" in \
		patch) NEW="$$MAJ.$$MIN.$$((PAT+1))" ;; \
		minor) NEW="$$MAJ.$$((MIN+1)).0" ;; \
		major) NEW="$$((MAJ+1)).0.0" ;; \
	esac; \
	echo "Bumping $(CHART): $$CURRENT -> $$NEW"; \
	sed -i.bak "s/^version:.*/version: $$NEW/" $(CHARTS_DIR)/$(CHART)/Chart.yaml; \
	rm $(CHARTS_DIR)/$(CHART)/Chart.yaml.bak; \
	echo ""; \
	echo "NEXT STEPS:"; \
	echo "  1. Add an entry under 'artifacthub.io/changes' in $(CHARTS_DIR)/$(CHART)/Chart.yaml"; \
	echo "  2. Update $(CHARTS_DIR)/$(CHART)/README.md if values/behavior changed"; \
	echo "  3. git add $(CHARTS_DIR)/$(CHART) && git commit -m 'feat($(CHART)): describe change'"; \
	echo "  4. git push (release.yml auto-triggers chart-releaser + GHCR push)"
