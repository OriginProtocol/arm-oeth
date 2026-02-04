# Deployment Framework

This framework manages smart contract deployments across multiple chains (Ethereum Mainnet, Sonic) with support for governance proposals, fork testing, and deployment history tracking.

## Architecture Overview

```
script/deploy/
├── DeployManager.s.sol    # Main orchestrator - runs deployment scripts
├── Base.s.sol             # Shared infrastructure (VM, Resolver, chain config)
├── helpers/
│   ├── AbstractDeployScript.s.sol  # Base class for deployment scripts
│   ├── DeploymentTypes.sol         # Shared types (State, Contract, etc.)
│   ├── GovHelper.sol               # Governance proposal utilities
│   ├── Logger.sol                  # Logging utilities
│   └── Resolver.sol                # Contract address registry
├── mainnet/               # Ethereum Mainnet deployment scripts
└── sonic/                 # Sonic chain deployment scripts
```

## How It Works

### Execution Flow

1. **DeployManager.setUp()** initializes the environment:
   - Determines deployment state (FORK_TEST, FORK_DEPLOYING, REAL_DEPLOYING)
   - Creates/loads the deployment JSON file (`build/deployments-{chainId}.json`)
   - Deploys the Resolver contract for address lookups

2. **DeployManager.run()** executes deployment scripts:
   - Loads existing deployment history into the Resolver
   - Reads scripts from the chain-specific folder (e.g., `mainnet/` or `sonic/`)
   - Processes only the last N scripts (default: 2) to improve efficiency
   - For each script: compiles, deploys, and executes via `_runDeployFile()`

3. **Each script** (inheriting from AbstractDeployScript):
   - Runs `_execute()` to deploy contracts
   - Registers deployed contracts via `_recordDeployment()`
   - Builds governance proposals via `_buildGovernanceProposal()`
   - Simulates governance execution in fork mode

### Deployment States

| State | Trigger | Behavior |
|-------|---------|----------|
| `FORK_TEST` | `forge test` | Simulates with `vm.prank`, uses temp deployment file |
| `FORK_DEPLOYING` | `forge script` (no --broadcast) | Dry-run simulation |
| `REAL_DEPLOYING` | `forge script --broadcast` | Real on-chain deployment |

### Deployment History

Deployments are tracked in JSON files:
- `build/deployments-1.json` - Ethereum Mainnet
- `build/deployments-146.json` - Sonic
- `build/deployments-fork-{timestamp}.json` - Temporary files for fork testing

Format:
```json
{
  "contracts": [
    { "name": "LIDO_ARM", "implementation": "0x..." },
    { "name": "LIDO_ARM_IMPL", "implementation": "0x..." }
  ],
  "executions": [
    { "name": "001_CoreMainnet", "timestamp": 1723685111 }
  ]
}
```

## Creating a New Deployment Script

### 1. Naming Convention

- **File**: `NNN_DescriptiveName.s.sol` (e.g., `017_UpgradeLidoARM.s.sol`)
- **Contract**: Same as filename, prefixed with `$` (e.g., `$017_UpgradeLidoARM`)
- **Constructor arg**: Same as contract name without `$`

### 2. Template

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";
import {GovHelper, GovProposal} from "script/deploy/helpers/GovHelper.sol";

contract $017_UpgradeLidoARM is AbstractDeployScript("017_UpgradeLidoARM") {
    using GovHelper for GovProposal;

    // Set to true to skip this script
    bool public constant override skip = false;

    // Set to true once governance proposal is executed on-chain
    bool public constant override proposalExecuted = false;

    function _execute() internal override {
        // 1. Get previously deployed contracts
        address proxy = resolver.implementations("LIDO_ARM");

        // 2. Deploy new contracts
        MyImpl impl = new MyImpl();

        // 3. Register deployments
        _recordDeployment("LIDO_ARM_IMPL", address(impl));
    }

    function _buildGovernanceProposal() internal override {
        govProposal.setDescription("Upgrade LidoARM");

        address proxy = resolver.implementations("LIDO_ARM");
        address impl = resolver.implementations("LIDO_ARM_IMPL");

        govProposal.action(proxy, "upgradeTo(address)", abi.encode(impl));
    }

    function _fork() internal override {
        // Post-deployment verification (runs after governance simulation)
    }
}
```

### 3. Key Functions

| Function | Purpose |
|----------|---------|
| `_execute()` | Deploy contracts, runs within broadcast/prank context |
| `_buildGovernanceProposal()` | Define governance actions |
| `_fork()` | Post-deployment verification (fork mode only) |
| `skip()` | Return `true` to skip this script |
| `proposalExecuted()` | Return `true` when governance is complete |

### 4. Resolver Usage

```solidity
// Get a previously deployed contract address
address proxy = resolver.implementations("LIDO_ARM");

// Register a newly deployed contract
_recordDeployment("MY_CONTRACT", address(myContract));
```

## Running Deployments

### Simulate (Dry Run)

```bash
# Mainnet simulation
make simulate

# Sonic simulation
make simulate NETWORK=sonic
```

### Deploy

```bash
# Mainnet
make deploy-mainnet

# Sonic
make deploy-sonic

# Holesky testnet
make deploy-holesky
```

### Local Testing

```bash
# Run against local Anvil node
make deploy-local
```

## Governance Proposals

When a script includes governance actions:

- **Fork mode**: The proposal is simulated end-to-end (timelock execution is fast-forwarded)
- **Real deployment**: Calldata is output for manual submission to the governance system

Example governance action:
```solidity
govProposal.action(
    targetAddress,
    "functionSignature(type1,type2)",
    abi.encode(param1, param2)
);
```

## Tips

1. **Always check `skip` and `proposalExecuted`** - Set `proposalExecuted = true` once governance passes to prevent re-execution.

2. **Use descriptive contract names** - Names like `LIDO_ARM_IMPL` are clearer than `IMPL_V2`.

3. **Test with fork first** - Run `make simulate` before real deployments.

4. **Scripts are processed in order** - Name files with numeric prefixes (001_, 002_, etc.).

5. **Only the last N scripts run** - By default, only the 2 most recent scripts are processed. Older scripts are skipped if already in deployment history.

6. **Reference the example** - See `mainnet/000_Example.s.sol` for a comprehensive template.
