PYTHON ?= python3

PACKAGE_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
SOURCES := $(shell find $(PACKAGE_DIR)/dashboards $(PACKAGE_DIR)/lib -type f \( -name '*.jsonnet' -o -name '*.libsonnet' \) | sort)
JSONNETFMT := $(PACKAGE_DIR)/.cache/tools/go-jsonnet-0.21.0/jsonnetfmt

.PHONY: bootstrap compile fmt fmt-check verify package-test clean

bootstrap:
	$(PYTHON) $(PACKAGE_DIR)/render_dashboards.py --bootstrap-only

compile:
	$(PYTHON) $(PACKAGE_DIR)/render_dashboards.py

fmt: bootstrap
	$(JSONNETFMT) -i $(SOURCES)

fmt-check: bootstrap
	$(JSONNETFMT) --test $(SOURCES)

verify: fmt-check compile
	$(PYTHON) $(PACKAGE_DIR)/verify_dashboards.py

package-test:
	@package_dir=$$(mktemp -d "$${TMPDIR:-/tmp}/oke-grafonnet-package.XXXXXX"); \
	trap 'rm -rf "$$package_dir"' EXIT; \
	cp -R $(PACKAGE_DIR)/dashboards $(PACKAGE_DIR)/lib "$$package_dir"; \
	cp $(PACKAGE_DIR)/jsonnetfile.json $(PACKAGE_DIR)/jsonnetfile.lock.json $(PACKAGE_DIR)/render_dashboards.py "$$package_dir"; \
	$(PYTHON) "$$package_dir/render_dashboards.py" --cache-dir "$$package_dir/.cache" --output-dir "$$package_dir/build"; \
	test "$$(find "$$package_dir/build" -type f -name '*.json' | wc -l | tr -d ' ')" = 21

clean:
	rm -rf $(PACKAGE_DIR)/build $(PACKAGE_DIR)/.cache
