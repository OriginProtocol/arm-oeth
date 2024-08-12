-include .env

.EXPORT_ALL_VARIABLES:
MAKEFLAGS += --no-print-directory

default:
	forge fmt && forge build

# Always keep Forge up to date
install:
	foundryup
	forge install

gas:
	@forge test --gas-report

# Generate gas snapshots for all your test functions
snapshot:
	@forge snapshot

# Tests
test:
	@forge test --summary

test-f-%:
	@FOUNDRY_MATCH_TEST=$* make test

test-c-%:
	@FOUNDRY_MATCH_CONTRACT=$* make test

# Coverage
coverage:
	@forge coverage --report lcov
	@lcov --ignore-errors unused --remove ./lcov.info -o ./lcov.info.pruned "test/*" "script/*"

coverage-html:
	@make coverage
	@genhtml ./lcov.info.pruned -o report --branch-coverage --output-dir ./coverage

# Run a script
simulate-s-%:
	@forge script script/$*.s.sol --fork-url $(PROVIDER_URL) -vvvvv

run-s-%:
	@forge script script/$*.s.sol --rpc-url $(PROVIDER_URL) --private-key ${DEPLOYER_PRIVATE_KEY} --broadcast --slow --verify -vvvvv

# Deploy scripts
deploy:
	@forge script script/001_OETH_ARM.s.sol --rpc-url $(PROVIDER_URL) --private-key ${DEPLOYER_PRIVATE_KEY} --broadcast --slow --verify -vvvv
#	@forge script script/deploy/DeployManager.sol --rpc-url $(PROVIDER_URL) --private-key ${DEPLOYER_PRIVATE_KEY} --broadcast --slow --verify -vvvv

deploy-testnet:
	@forge script script/001_OETH_ARM.s.sol --rpc-url $(TESTNET_URL) --private-key ${DEPLOYER_PRIVATE_KEY} --broadcast --slow -vvvv
#	@forge script script/deploy/DeployManager.sol --rpc-url $(TESTNET_URL) --private-key ${DEPLOYER_PRIVATE_KEY} --broadcast --slow -vvvv

deploy-holesky:
	@forge script script/001_OETH_ARM.s.sol --rpc-url $(HOLESKY_URL) --private-key ${DEPLOYER_PRIVATE_KEY} --broadcast --slow --verify -vvvv
#	@forge script script/deploy/DeployManager.sol --rpc-url $(HOLESKY_URL) --private-key ${HOLESKY_DEPLOYER_PRIVATE_KEY} --broadcast --slow --verify -vvvv

# Upgrade scripts
upgrade:
	@forge script script/002_Upgrade.s.sol --rpc-url $(PROVIDER_URL) --private-key ${DEPLOYER_PRIVATE_KEY} --broadcast --slow --verify -vvvv

upgrade-testnet:
	@forge script script/002_Upgrade.s.sol --rpc-url $(TESTNET_URL) --private-key ${DEPLOYER_PRIVATE_KEY} --broadcast --slow -vvvv

upgrade-holesky:
	@forge script script/002_Upgrade.s.sol --rpc-url $(HOLESKY_URL) --private-key ${DEPLOYER_PRIVATE_KEY} --broadcast --slow --verify -vvvv

# Tasks
simulate-t-swap:
	forge clean
	forge script script/999_Tasks.s.sol --fork-url $(PROVIDER_URL) -vvvvv -s "swap(address,address,uint256)" $(FROM) $(TO) $(AMOUNT)

run-t-swap:
	forge clean
	forge script script/999_Tasks.s.sol --rpc-url $(PROVIDER_URL) --private-key ${DEPLOYER_PRIVATE_KEY} --broadcast --slow --verify -vvvvv -s "swap(address,address,uint256)" $(FROM) $(TO) $(AMOUNT)

# Override default `test` and `coverage` targets
.PHONY: test coverage