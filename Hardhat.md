# Hardhat Tasks

## Request a OETH withdraw

1. Start a local Anvil node forked from the latest block

```
export PROVIDER_URL=
anvil --fork-url="$PROVIDER_URL"
```

2. In a separate terminal, run the `requestWithdraw` task against the local fork.

```
unset DEFENDER_API_KEY
unset DEFENDER_API_SECRET
export IMPERSONATE=0x39878253374355DBcc15C86458F084fb6f2d6DE7
export DEBUG=origin*
npx hardhat requestWithdraw --amount 300 --network local
```

3. Create a Relayer API key

See [Generate Relayer API key](./README.md#generate-relayer-api-key) instructions in the README.

4.  Run the real thing after generating an API key for the Relay account

```
unset IMPERSONATE
export DEFENDER_API_KEY=
export DEFENDER_API_SECRET=
export DEBUG=origin*
npx hardhat requestWithdraw --amount 300 --network mainnet
```

5. Delete the Relayer API key

For more information, see the `requestWithdraw` help

```
npx hardhat requestWithdraw --help
```

## Claim all claimable OETH withdraw requests

1. Start a local Anvil node forked from the latest block

```
anvil --fork-url="$PROVIDER_URL"
```

2. In a separate terminal, run the `autoClaimWithdraw` task against the local fork.

```
unset DEFENDER_API_KEY
unset DEFENDER_API_SECRET
export IMPERSONATE=0x39878253374355DBcc15C86458F084fb6f2d6DE7
export DEBUG=origin*
npx hardhat autoClaimWithdraw --network local
```

3. Create a Relayer API key

See [Generate Relayer API key](./README.md#generate-relayer-api-key) instructions in the README.

4.  Run the real thing after generating an API key for the Relay account

```
unset IMPERSONATE
export DEFENDER_API_KEY=
export DEFENDER_API_SECRET=
export DEBUG=origin*
npx hardhat autoClaimWithdraw --network mainnet
```

5. Delete the Relayer API key

For more information, see the `autoClaimWithdraw` help

```
npx hardhat autoClaimWithdraw --help
```
