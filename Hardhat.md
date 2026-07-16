# Hardhat Tasks

## Request a OETH withdraw

1. Start a local Anvil node forked from the latest block

```
export MAINNET_URL=
anvil --fork-url="$MAINNET_URL"
```

2. In a separate terminal, run the `requestWithdraw` task against the local fork.

```
export IMPERSONATE=0x39878253374355DBcc15C86458F084fb6f2d6DE7
export DEBUG=origin*
yarn hardhat requestWithdraw --amount 300 --network local
```

3. Run the real task from an environment with AWS KMS credentials configured.

```
unset IMPERSONATE
export DEBUG=origin*
yarn hardhat requestWithdraw --amount 300 --network mainnet
```

For more information, see the `requestWithdraw` help

```
yarn hardhat requestWithdraw --help
```

## Claim all claimable OETH withdraw requests

1. Start a local Anvil node forked from the latest block

```
anvil --fork-url="$MAINNET_URL"
```

2. In a separate terminal, run the `autoClaimWithdraw` task against the local fork.

```
export IMPERSONATE=0x39878253374355DBcc15C86458F084fb6f2d6DE7
export DEBUG=origin*
yarn hardhat autoClaimWithdraw --network local
```

3. Run the real task from an environment with AWS KMS credentials configured.

```
unset IMPERSONATE
export DEBUG=origin*
yarn hardhat autoClaimWithdraw --network mainnet
```

For more information, see the `autoClaimWithdraw` help

```
yarn hardhat autoClaimWithdraw --help
```
