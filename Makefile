-include .env

.EXPORT_ALL_VARIABLES:
MAKEFLAGS += --no-print-directory

default:
	forge fmt && forge build

# Always keep Forge up to date
install:
	foundryup
	forge soldeer install
	yarn install

clean:
	@rm -rf broadcast cache out

# Remove every "crytic-export" directory anywhere in the project
clean-crytic:
	@find . -type d -name crytic-export -exec rm -rf '{}' +

clean-all: 
	@rm -rf broadcast cache out dependencies node_modules soldeer.lock yarn.lock .lcov.info lcov.info pruned artifacts cache hardhat-node_modules
	@$(MAKE) clean-crytic


gas:
	@forge test --gas-report

# Generate gas snapshots for all your test functions
snapshot:
	@forge snapshot

# Tests
test-std:
	forge test --summary --fail-fast --show-progress

test:
	@FOUNDRY_NO_MATCH_CONTRACT=Fuzzer $(MAKE) test-std

test-f-%:
	@FOUNDRY_MATCH_TEST=$* $(MAKE) test-std

test-c-%:
	@FOUNDRY_MATCH_CONTRACT=$* $(MAKE) test-std

test-all:
	@$(MAKE) test-std

test-invariant-lido:
	@FOUNDRY_INVARIANT_FAIL_ON_REVERT=false FOUNDRY_MATCH_CONTRACT=FuzzerFoundry_OethARM $(MAKE) test-std

test-invariant-origin:
	@FOUNDRY_INVARIANT_FAIL_ON_REVERT=true FOUNDRY_MATCH_CONTRACT=FuzzerFoundry_OriginARM $(MAKE) test-std

test-invariant-ethena:
	@FOUNDRY_INVARIANT_FAIL_ON_REVERT=true FOUNDRY_MATCH_CONTRACT=FuzzerFoundry_EthenaARM $(MAKE) test-std

test-invariants:
	@$(MAKE) test-invariant-lido && $(MAKE) test-invariant-origin && $(MAKE) test-invariant-ethena

test-unit:
	@FOUNDRY_MATCH_PATH='test/unit/**' $(MAKE) test-std

test-fork:
	@FOUNDRY_MATCH_PATH='test/fork/**' $(MAKE) test-std

test-smoke:
	@FOUNDRY_MATCH_PATH='test/smoke/**' $(MAKE) test-std


# Coverage
coverage:
	@forge coverage --report lcov

coverage-html:
	@make coverage
	@genhtml ./lcov.info.pruned -o report --branch-coverage --output-dir ./coverage

# Run a script
simulate-s-%:
	@forge script script/deploy/$*.sol --fork-url $(PROVIDER_URL) -vvvvv

simulate-sonic-s-%:
	@forge script script/deploy/$*.sol --fork-url $(SONIC_URL) -vvvvv

run-s-%:
	@forge script script/deploy/$*.sol --rpc-url $(PROVIDER_URL) --account deployerKey --sender $(DEPLOYER_ADDRESS) --broadcast --slow --verify -vvvvv

run-sonic-s-%:
	@forge script script/deploy/$*.sol --rpc-url $(SONIC_URL) --account deployerKey --sender $(DEPLOYER_ADDRESS) --broadcast --slow --verify -vvvvv

# Deploy scripts
deploy:
	@forge script script/deploy/DeployManager.sol --rpc-url $(PROVIDER_URL) --account deployerKey --sender $(DEPLOYER_ADDRESS) --broadcast --slow --verify -vvvv

deploy-local:
	@forge script script/deploy/DeployManager.sol --rpc-url $(LOCAL_URL) --account deployerKey --sender $(DEPLOYER_ADDRESS) --broadcast --slow -vvvv

deploy-testnet:
	@forge script script/deploy/DeployManager.sol --rpc-url $(TESTNET_URL) --broadcast --slow --unlocked -vvvv

deploy-holesky:
	@forge script script/deploy/DeployManager.sol --rpc-url $(HOLESKY_URL) --account deployerKey --sender $(DEPLOYER_ADDRESS) --broadcast --slow --verify -vvv

deploy-sonic:
	@forge script script/deploy/DeployManager.sol --rpc-url $(SONIC_URL) --account deployerKey --sender $(DEPLOYER_ADDRESS) --broadcast --slow --verify -vvv

simulate-deploys:
	@forge script script/deploy/DeployManager.sol --fork-url $(PROVIDER_URL) -vvvv

simulate-sonic-deploys:
	@forge script script/deploy/DeployManager.sol --fork-url $(SONIC_URL) -vvvv

# Usage : make verify file=src/contracts/Proxy.sol addr=0xCED...
SHELL := /bin/bash
match:
	@if [ -z "$(file)" ] || [ -z "$(addr)" ]; then \
		echo "Usage: make verify file=<path> addr=<address>"; \
		exit 1; \
	fi
	@name=$$(basename $(file) .sol); \
	diff <(forge flatten $(file)) <(cast source --flatten $(addr)) \
	&& printf "✅ Success: Local contract %-20s matches deployment at $(addr)\n" "$$name" \
	|| printf "❌ Failure: Local contract %-20s differs from deployment at $(addr)\n" "$$name"


# Override default `test` and `coverage` targets
.PHONY: test coverage match
