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

.PHONY: scaffold
scaffold: ## Copy an existing chart as starting point. Usage: make scaffold CHART=<new> FROM=<existing>
	@if [ -z "$(CHART)" ] || [ -z "$(FROM)" ]; then echo "Usage: make scaffold CHART=<new> FROM=<existing>"; exit 1; fi
	@if [ -d "$(CHARTS_DIR)/$(CHART)" ]; then echo "ERROR: chart already exists: $(CHARTS_DIR)/$(CHART)"; exit 1; fi
	@if [ ! -d "$(CHARTS_DIR)/$(FROM)" ]; then echo "ERROR: source chart not found: $(CHARTS_DIR)/$(FROM)"; exit 1; fi
	cp -r $(CHARTS_DIR)/$(FROM) $(CHARTS_DIR)/$(CHART)
	@sed -i.bak "s/^name:.*/name: $(CHART)/" $(CHARTS_DIR)/$(CHART)/Chart.yaml
	@sed -i.bak "s/^version:.*/version: 0.1.0/" $(CHARTS_DIR)/$(CHART)/Chart.yaml
	@rm $(CHARTS_DIR)/$(CHART)/Chart.yaml.bak
	@echo "Scaffolded: $(CHARTS_DIR)/$(CHART) (copied from $(FROM), name renamed, version reset to 0.1.0)"
	@echo ""
	@echo "NEXT STEPS:"
	@echo "  1. Edit $(CHARTS_DIR)/$(CHART)/Chart.yaml — description, keywords, artifacthub.io/changes"
	@echo "  2. Replace $(CHARTS_DIR)/$(CHART)/values.yaml and values.schema.json with the new chart's schema"
	@echo "  3. Replace templates/ with the new chart's manifests"
	@echo "  4. Rewrite $(CHARTS_DIR)/$(CHART)/README.md"
	@echo "  5. make lint CHART=$(CHART) && make template CHART=$(CHART)"

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
template: ## helm template render smoke test (CHART=name to limit). Picks up charts/<name>/ci/*.yaml if present.
	@for c in $(TARGET_CHARTS); do \
		echo "==> helm template $$c"; \
		ci_args=""; \
		for f in $(CHARTS_DIR)/$$c/ci/*.yaml; do \
			[ -f "$$f" ] && ci_args="$$ci_args -f $$f"; \
		done; \
		helm template ci $(CHARTS_DIR)/$$c $$ci_args > /dev/null; \
	done

.PHONY: validate
validate: ## kubeconform validation against k8s + CRD schemas (CHART=name to limit). Picks up charts/<name>/ci/*.yaml if present.
	@command -v kubeconform >/dev/null 2>&1 || { echo "kubeconform required: brew install kubeconform"; exit 1; }
	@for c in $(TARGET_CHARTS); do \
		echo "==> kubeconform $$c"; \
		ci_args=""; \
		for f in $(CHARTS_DIR)/$$c/ci/*.yaml; do \
			[ -f "$$f" ] && ci_args="$$ci_args -f $$f"; \
		done; \
		helm template ci $(CHARTS_DIR)/$$c $$ci_args | kubeconform \
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
	echo "  2. Run 'make changelog CHART=$(CHART)' to update CHANGELOG.md"; \
	echo "  3. Update $(CHARTS_DIR)/$(CHART)/README.md if values/behavior changed"; \
	echo "  4. git add $(CHARTS_DIR)/$(CHART) && git commit -m 'feat($(CHART)): describe change'"; \
	echo "  5. git push (release.yml auto-triggers chart-releaser + GHCR push)"

.PHONY: changelog
changelog: ## Sync CHART CHANGELOG.md from Chart.yaml. Usage: make changelog CHART=<name> [DRY_RUN=1]
	@if [ -z "$(CHART)" ]; then echo "ERROR: CHART is required (e.g. make changelog CHART=nginx-gateway-cr)"; exit 1; fi
	@if [ ! -d "$(CHARTS_DIR)/$(CHART)" ]; then echo "ERROR: chart not found: $(CHARTS_DIR)/$(CHART)"; exit 1; fi
	@./scripts/changelog/sync-changelog.sh $(if $(DRY_RUN),--dry-run) $(CHARTS_DIR)/$(CHART)

.PHONY: changelog-all
changelog-all: ## Sync CHANGELOG.md for every chart (used for backfill / CI sanity).
	@./scripts/changelog/sync-changelog.sh $(if $(DRY_RUN),--dry-run) --all

##@ Upgrade-sync (chart upgrade.sh body propagation)

.PHONY: sync-check
sync-check: ## Verify each chart's upgrade.sh body matches its declared template (CI guard).
	@./scripts/upgrade-sync/sync.sh --check

.PHONY: sync-apply
sync-apply: ## Rewrite each chart's upgrade.sh body from its template. Refuses on dirty tree.
	@./scripts/upgrade-sync/sync.sh --apply

.PHONY: sync-list
sync-list: ## List managed charts and their templates.
	@./scripts/upgrade-sync/sync.sh --list

.PHONY: sync-status
sync-status: ## List every chart with classification (managed / unmanaged / missing-template).
	@./scripts/upgrade-sync/sync.sh --status

##@ Version drift (upstream tracking + auto-bump)

.PHONY: version-check
version-check: ## Drift-only report (read-only, no file or branch changes).
	@./scripts/check-version/check-version.sh --check

.PHONY: version-apply
version-apply: ## For each drifted chart: bump + ci + branch + commit + push + open PR.
	@./scripts/check-version/check-version.sh --apply

##@ Shell scripts

# Discovered once at make startup. SYNTAX_TARGETS covers every maintainer
# script plus the per-chart upgrade.sh files that get propagated from the
# templates — `bash -n` and `zsh -n` are run against all of them.
# SHELLCHECK_TARGETS is narrower: per-chart upgrade.sh is the sync output of
# scripts/upgrade-sync/templates/, so shellchecking both is redundant. We
# only run shellcheck against the source-of-truth under scripts/, and only
# at --severity=error (info/warning are advisory and shown but do not fail).
# STRICT=1 turns "shellcheck not installed" into a hard failure (e.g. CI).
SYNTAX_TARGETS     := $(shell find scripts -type f -name '*.sh' 2>/dev/null | sort) $(wildcard $(CHARTS_DIR)/*/upgrade.sh)
SHELLCHECK_TARGETS := $(shell find scripts -type f -name '*.sh' 2>/dev/null | sort)

.PHONY: shell-lint
shell-lint: ## Lint repo shell scripts: bash -n + zsh -n on every script, shellcheck (--severity=error) on scripts/ only. STRICT=1 to require shellcheck.
	@if [ -z "$(SYNTAX_TARGETS)" ]; then \
		echo "shell-lint: no scripts found"; exit 0; \
	fi; \
	rc=0; \
	echo "==> bash -n  ($(words $(SYNTAX_TARGETS)) files)"; \
	for f in $(SYNTAX_TARGETS); do \
		bash -n "$$f" || { echo "FAIL bash -n: $$f"; rc=1; }; \
	done; \
	if command -v zsh >/dev/null 2>&1; then \
		echo "==> zsh -n   ($(words $(SYNTAX_TARGETS)) files)"; \
		for f in $(SYNTAX_TARGETS); do \
			zsh -n "$$f" || { echo "FAIL zsh -n: $$f"; rc=1; }; \
		done; \
	else \
		echo "==> zsh -n   skipped (zsh not installed)"; \
	fi; \
	if command -v shellcheck >/dev/null 2>&1; then \
		echo "==> shellcheck --severity=error ($(words $(SHELLCHECK_TARGETS)) files; advisory output for warning/info)"; \
		shellcheck --severity=error $(SHELLCHECK_TARGETS) || rc=1; \
		echo "--- advisory shellcheck output (warning/info, not fail) ---"; \
		shellcheck --severity=warning $(SHELLCHECK_TARGETS) || true; \
	else \
		msg="shellcheck not installed (brew install shellcheck)"; \
		if [ -n "$(STRICT)" ]; then \
			echo "==> shellcheck FAIL: $$msg (STRICT=1)"; rc=1; \
		else \
			echo "==> shellcheck skipped: $$msg"; \
		fi; \
	fi; \
	exit $$rc
