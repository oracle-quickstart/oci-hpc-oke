PYTHON ?= python3
INCLUDE_KUEUE ?= false

PACKAGE_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
SOURCES := $(shell find $(PACKAGE_DIR)/dashboards $(PACKAGE_DIR)/lib -type f \( -name '*.jsonnet' -o -name '*.libsonnet' \) | sort)
JSONNETFMT := $(PACKAGE_DIR)/.cache/tools/go-jsonnet-0.21.0/jsonnetfmt

.PHONY: bootstrap compile fmt fmt-check verify package-test clean

bootstrap:
	$(PYTHON) $(PACKAGE_DIR)/render_dashboards.py --bootstrap-only

compile:
	$(PYTHON) $(PACKAGE_DIR)/render_dashboards.py $(if $(filter true,$(INCLUDE_KUEUE)),--include-kueue,)

fmt: bootstrap
	$(JSONNETFMT) -i $(SOURCES)

fmt-check: bootstrap
	$(JSONNETFMT) --test $(SOURCES)

verify: INCLUDE_KUEUE = true
verify: fmt-check compile
	$(PYTHON) $(PACKAGE_DIR)/verify_dashboards.py

package-test:
	@package_dir=$$(mktemp -d "$${TMPDIR:-/tmp}/oke-grafonnet-package.XXXXXX"); \
	trap 'rm -rf "$$package_dir"' EXIT; \
	cp -R $(PACKAGE_DIR)/dashboards $(PACKAGE_DIR)/lib "$$package_dir"; \
	cp $(PACKAGE_DIR)/jsonnetfile.json $(PACKAGE_DIR)/jsonnetfile.lock.json $(PACKAGE_DIR)/render_dashboards.py "$$package_dir"; \
	$(PYTHON) "$$package_dir/render_dashboards.py" --cache-dir "$$package_dir/.cache" --output-dir "$$package_dir/build" --include-kueue; \
	test "$$(find "$$package_dir/build" -type f -name '*.json' | wc -l | tr -d ' ')" = 23

clean:
	rm -rf $(PACKAGE_DIR)/build $(PACKAGE_DIR)/.cache
