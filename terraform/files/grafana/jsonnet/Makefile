JSONNET ?= jsonnet
JSONNETFMT ?= jsonnetfmt
JB ?= jb

PACKAGE_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
DASHBOARDS := $(shell find $(PACKAGE_DIR)/dashboards -type f -name '*.jsonnet' | sort)
SOURCES := $(shell find $(PACKAGE_DIR)/dashboards $(PACKAGE_DIR)/lib -type f \( -name '*.jsonnet' -o -name '*.libsonnet' \) | sort)

.PHONY: bootstrap compile fmt fmt-check clean

bootstrap:
	$(JB) install

compile:
	mkdir -p $(PACKAGE_DIR)/build
	@for source in $(DASHBOARDS); do \
		name=$$(basename "$$source" .jsonnet); \
		$(JSONNET) -J $(PACKAGE_DIR)/vendor \
			--output-file "$(PACKAGE_DIR)/build/$$name.json" "$$source" || exit 1; \
	done

fmt:
	$(JSONNETFMT) -i $(SOURCES)

fmt-check:
	$(JSONNETFMT) --test $(SOURCES)

clean:
	rm -rf $(PACKAGE_DIR)/build
