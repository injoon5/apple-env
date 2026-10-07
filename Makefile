# Everyday tasks. `make` lists them.
SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

APP := MyApp
CONFIG ?= debug
UNAME := $(shell uname -s)
ENV := . scripts/env.sh &&
# Large projects need more open files than a login shell allows.
ULIMIT := { ulimit -n 65536 2>/dev/null || true; } &&
SWIFT_PATHS := Package.swift Sources Core

.PHONY: help setup doctor test lint format build run xcode ship upload sdk-pack rename clean

help: ## List tasks
	@grep -hE '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "} {printf "  \033[1m%-9s\033[0m %s\n", $$1, $$2}'

setup: ## Install the toolchain for this machine (safe to re-run)
	@scripts/bootstrap.sh

doctor: ## Show what this machine can build, run and ship
	@scripts/doctor.sh

test: ## Run the Core tests (no iOS SDK needed)
	@$(ENV) swift test --package-path Core

lint: ## Check formatting with swift-format
	@$(ENV) swift format lint --strict --recursive --parallel $(SWIFT_PATHS)

format: ## Format all Swift sources in place
	@$(ENV) swift format format --in-place --recursive --parallel $(SWIFT_PATHS)

ifeq ($(UNAME),Darwin)

build: ## Build the iOS app (CONFIG=release for a release build)
	@xcodegen generate --quiet
	@xcodebuild -project $(APP).xcodeproj -scheme $(APP) -configuration $(if $(filter release,$(CONFIG)),Release,Debug) \
		-destination 'generic/platform=iOS Simulator' -derivedDataPath .build/xcode \
		CODE_SIGNING_ALLOWED=NO -quiet build
	@echo "Build succeeded: .build/xcode/Build/Products/$(if $(filter release,$(CONFIG)),Release,Debug)-iphonesimulator/$(APP).app"

run: ## Run on a device (Linux: iPhone over USB; macOS: from Xcode)
	@echo "On macOS, run from Xcode: make xcode, pick a simulator or your iPhone, press Cmd-R."

xcode: ## Generate the Xcode project and open it (macOS)
	@if [ ! -f Config/Local.xcconfig ] && [ -n "$${DEVELOPMENT_TEAM:-}" ]; then \
		echo "DEVELOPMENT_TEAM = $$DEVELOPMENT_TEAM" > Config/Local.xcconfig; fi
	@xcodegen generate --quiet
	@open $(APP).xcodeproj

ship: ## Build and validate an App Store .ipa (Linux; macOS: Xcode Archive)
	@echo "On macOS, ship from Xcode: make xcode, then Product > Archive > Distribute App."

upload: ## Ship and upload to TestFlight (needs ASC_KEY_PATH, ASC_ISSUER_ID, ASC_KEY_ID)
	@echo "On macOS, ship from Xcode: make xcode, then Product > Archive > Distribute App."

else

# xtool crashes without an iOS SDK; say what to do instead.
REQUIRE_SDK := swift sdk list 2>/dev/null | grep -qw darwin || { \
	echo "No iOS SDK installed. See README, 'iOS SDK' (e.g. set APPLE_SDK_PASSPHRASE, then make setup)." >&2; exit 1; } &&

build:
	@$(ENV) $(REQUIRE_SDK) $(ULIMIT) xtool dev build --configuration $(CONFIG)

run:
	@$(ENV) $(REQUIRE_SDK) $(ULIMIT) xtool dev run --configuration $(CONFIG)

xcode:
	@echo "make xcode needs macOS. On Linux use make build and make run."

ship:
	@$(ENV) $(REQUIRE_SDK) $(ULIMIT) "$$APPLE_ENV_UPSTREAM/ship.sh"

upload:
	@$(ENV) $(REQUIRE_SDK) $(ULIMIT) "$$APPLE_ENV_UPSTREAM/ship.sh" --upload

endif

sdk-pack: ## Archive the iOS SDK for Linux machines (macOS: from Xcode; Linux: installed SDK)
	@$(ENV) scripts/sdk.sh pack

rename: ## Rename the app: make rename NAME=Notes BUNDLE_ID=com.you.notes
	@scripts/rename.sh "$(NAME)" "$(BUNDLE_ID)"

clean: ## Remove build output
	rm -rf .build Core/.build xtool $(APP).xcodeproj
