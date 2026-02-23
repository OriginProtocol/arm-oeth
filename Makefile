-include .env

.EXPORT_ALL_VARIABLES:
MAKEFLAGS += --no-print-directory

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                                 VARIABLES                                    ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

DEPLOY_SCRIPT   := script/deploy/DeployManager.s.sol
DEPLOY_BASE     := --account deployerKey --sender $(DEPLOYER_ADDRESS) --broadcast --slow

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                                  DEFAULT                                     ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

default:
	forge fmt
	forge build

install:
	foundryup --version stable
	forge soldeer install
	yarn install

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                                   CLEAN                                      ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

clean:
	rm -rf broadcast cache out
	find build -name '*fork*' -delete 2>/dev/null || true

clean-crytic:
	find . -type d -name crytic-export -exec rm -rf '{}' +

clean-all: clean clean-crytic
	rm -rf dependencies node_modules soldeer.lock yarn.lock lcov.info coverage artifacts hardhat-node_modules

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                                   TESTS                                      ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# Base test command
test-base:
	forge test --summary --fail-fast --show-progress -vvv

# Run all tests (excluding fuzzers by default)
test:
	FOUNDRY_NO_MATCH_CONTRACT=Fuzzer $(MAKE) test-base

# Run tests matching a function name: make test-f-testSwap
test-f-%:
	FOUNDRY_MATCH_TEST=$* $(MAKE) test-base

# Run tests matching a contract name: make test-c-LidoARM
test-c-%:
	FOUNDRY_MATCH_CONTRACT=$* $(MAKE) test-base

# Run tests by category
test-unit:
	FOUNDRY_MATCH_PATH='test/unit/**' $(MAKE) test-base

test-fork:
	FOUNDRY_MATCH_PATH='test/fork/**' $(MAKE) test-base

test-smoke:
	forge build
	FOUNDRY_MATCH_PATH='test/smoke/**' $(MAKE) test-base

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                              INVARIANT TESTS                                 ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# Run a single invariant test: make test-invariant-lido
test-invariant-%:
	$(eval FAIL_ON_REVERT := $(if $(filter lido,$*),false,true))
	$(eval CONTRACT := $(shell echo $* | awk '{print toupper(substr($$0,1,1)) substr($$0,2)}')ARM)
	FOUNDRY_INVARIANT_FAIL_ON_REVERT=$(FAIL_ON_REVERT) FOUNDRY_MATCH_CONTRACT=FuzzerFoundry_$(CONTRACT) $(MAKE) test-base

# Run all invariant tests
test-invariants:
	$(MAKE) test-invariant-lido
	$(MAKE) test-invariant-origin
	$(MAKE) test-invariant-ethena

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                                 COVERAGE                                     ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

coverage:
	forge coverage --report lcov

coverage-html: coverage
	genhtml ./lcov.info -o coverage --branch-coverage

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                                   GAS                                        ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

gas:
	forge test --gas-report

snapshot:
	forge snapshot

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                                  DEPLOY                                      ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

deploy-mainnet:
	forge build
	@forge script $(DEPLOY_SCRIPT) --rpc-url $(MAINNET_URL) $(DEPLOY_BASE) --verify -vvvv

deploy-local:
	forge build
	@forge script $(DEPLOY_SCRIPT) --rpc-url $(LOCAL_URL) $(DEPLOY_BASE) -vvvv

deploy-testnet:
	forge build
	@forge script $(DEPLOY_SCRIPT) --rpc-url $(TESTNET_URL) --broadcast --slow --unlocked -vvvv

deploy-sonic:
	forge build
	@forge script $(DEPLOY_SCRIPT) --rpc-url $(SONIC_URL) $(DEPLOY_BASE) --verify -vvv

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                                 SIMULATE                                     ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# Simulate deployment: make simulate (mainnet) or make simulate NETWORK=sonic
NETWORK ?= mainnet
simulate:
	forge build
	@forge script $(DEPLOY_SCRIPT) --fork-url $(if $(filter sonic,$(NETWORK)),$(SONIC_URL),$(MAINNET_URL)) -vvvv

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                            UPDATE DEPLOYMENTS                                ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

update-deployments:
	forge build
	@forge script script/automation/UpdateGovernanceMetadata.s.sol --fork-url $(MAINNET_URL) -vvvv

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                                  VERIFY                                      ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# Compare local contract with deployed bytecode
# Usage: make verify-match file=src/contracts/Proxy.sol addr=0xCED...
SHELL := /bin/bash
match:
	@if [ -z "$(file)" ] || [ -z "$(addr)" ]; then \
		echo "Usage: make verify-match file=<path> addr=<address>"; \
		exit 1; \
	fi
	@name=$$(basename $(file) .sol); \
	diff <(forge flatten $(file)) <(cast source --flatten $(addr)) \
	&& printf "✅ Success: Local contract %-20s matches deployment at $(addr)\n" "$$name" \
	|| printf "❌ Failure: Local contract %-20s differs from deployment at $(addr)\n" "$$name"

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                                  UTILS                                       ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# Print a frame with centered text: make frame text="SECTION NAME"
frame:
	@if [ -z "$(text)" ]; then echo "Usage: make frame text=\"SECTION NAME\""; exit 1; fi
	@awk -v t="$(text)" 'BEGIN { \
		w=78; \
		printf "// ╔"; for(i=0;i<w;i++) printf "═"; print "╗"; \
		pad=int((w-length(t))/2); \
		printf "// ║"; for(i=0;i<pad;i++) printf " "; printf "%s", t; \
		for(i=0;i<w-pad-length(t);i++) printf " "; print "║"; \
		printf "// ╚"; for(i=0;i<w;i++) printf "═"; print "╝"; \
	}'

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                                  PHONY                                       ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

.PHONY: test test-base test-unit test-fork test-smoke test-invariants \
        coverage coverage-html gas snapshot \
        deploy-mainnet deploy-local deploy-testnet deploy-sonic simulate \
        update-deployments match clean clean-crytic clean-all install frame
