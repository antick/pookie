SHELL := /bin/bash
CONFIG ?= debug
ROOT := $(CURDIR)
export CLANG_MODULE_CACHE_PATH := $(ROOT)/.build/modulecache
export SWIFTPM_MODULECACHE_OVERRIDE := $(ROOT)/.build/modulecache
SWIFT_FLAGS := --disable-sandbox --arch arm64
# Swift 6's build engine may use .build/out/Products rather than .build/debug.
BIN = $(shell swift build -c $(CONFIG) $(SWIFT_FLAGS) --show-bin-path)/Pookie

.PHONY: help build dev run selftest test script-tests verify-dev poses cli bundle open release clean

help:
	@echo "Pookie — desktop cat"
	@echo "  make build         compile ($(CONFIG), arm64)"
	@echo "  make dev           build and open Pookie Dev.app"
	@echo "  make run           run Pookie Dev.app with verbose logging"
	@echo "  make selftest      run headless pet checks"
	@echo "  make test          selftests, Swift tests and script safety tests"
	@echo "  make script-tests  release policy, native binaries and signatures"
	@echo "  make verify-dev    bundle identity, icons, notices and runtime checks"
	@echo "  make poses         render the artwork review sheets"
	@echo "  make bundle        assemble build/Pookie Dev.app"
	@echo "  make open          bundle and launch Pookie Dev.app"
	@echo "  make release       sign/notarize production artifacts and generate feed"
	@echo "  make clean         remove build artifacts"

build:
	@mkdir -p "$(CLANG_MODULE_CACHE_PATH)"
	swift build -c $(CONFIG) $(SWIFT_FLAGS)

run:
	@CONFIG=$(CONFIG) ./scripts/dev.sh --verbose

dev: open

selftest: build
	@"$(BIN)" --selftest

test: selftest
	swift test -c $(CONFIG) $(SWIFT_FLAGS)
	@$(MAKE) script-tests

script-tests:
	@python3 -m unittest discover -s scripts/release -p 'test_*.py'
	@./scripts/release/test-signatures.sh
	@for script in scripts/*.sh scripts/release/*.sh; do bash -n "$$script" || exit; done

verify-dev:
	@./scripts/test-bundle.sh

poses: build
	@mkdir -p shots
	@"$(BIN)" --render-png shots/poses.png
	@"$(BIN)" --render-species shots/species.png
	@"$(BIN)" --render-patterns shots/patterns.png
	@"$(BIN)" --render-brawl shots/brawl.png

cli: bundle
	@ln -sf "$(CURDIR)/build/Pookie Dev.app/Contents/MacOS/Pookie" build/pookie
	@echo "build/pookie -> Pookie Dev; add $(CURDIR)/build to PATH"

bundle:
	@./scripts/bundle.sh $(CONFIG) development

open: bundle
	@open "build/Pookie Dev.app"

release:
	@./scripts/package-macos.sh
	@./scripts/release/appcast.sh

clean:
	rm -rf .build build
