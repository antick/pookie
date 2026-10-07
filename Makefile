SHELL := /bin/bash
CONFIG ?= debug

# SwiftPM needs a writable Clang module cache and, in restricted shells,
# --disable-sandbox (it wraps manifest compilation in sandbox-exec).
ROOT := $(PWD)
export CLANG_MODULE_CACHE_PATH := $(ROOT)/.build/modulecache
export SWIFTPM_MODULECACHE_OVERRIDE := $(ROOT)/.build/modulecache

SWIFT_FLAGS := --disable-sandbox
BIN := ./.build/$(CONFIG)/Pookie

.PHONY: help build run selftest poses bundle open clean

help:
	@echo "Pookie — desktop cat"
	@echo ""
	@echo "  make build      compile ($(CONFIG))"
	@echo "  make run        compile and run with verbose logging"
	@echo "  make selftest   headless checks (bitmap layout, silhouette, physics, postures)"
	@echo "  make poses      render shots/poses.png for eyeballing the artwork"
	@echo "  make bundle     assemble build/Pookie.app"
	@echo "  make open       bundle and launch the app"
	@echo "  make clean      remove build artefacts"

build:
	@mkdir -p $(ROOT)/.build/modulecache
	swift build -c $(CONFIG) $(SWIFT_FLAGS)

run: build
	$(BIN) --verbose

selftest: build
	@$(BIN) --selftest

poses: build
	@mkdir -p shots
	@$(BIN) --render-png shots/poses.png
	@$(BIN) --render-species shots/species.png
	@$(BIN) --render-patterns shots/patterns.png
	@$(BIN) --render-brawl shots/brawl.png

bundle:
	@./scripts/bundle.sh $(CONFIG)

open: bundle
	@open build/Pookie.app

clean:
	rm -rf .build build
