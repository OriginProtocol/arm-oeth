# Code Standards

Solidity code quality standards covering NatSpec documentation, file structure, naming conventions, gas optimization patterns, and testing standards. Used by the writer agent when generating code.

---

## NatSpec Documentation

### Contract Level

```solidity
/// @title LidoARM - Automated Redemption Manager for stETH/WETH
/// @notice Provides swap and LP functionality for stETH/WETH pair using dual pricing
/// @author Origin Protocol
/// @dev Inherits AbstractARM. Overrides _externalWithdrawQueue for Lido-specific withdrawals.
contract LidoARM is AbstractARM {
```

Required: `@title`, `@notice`. Use `@author` for attribution. Use `@dev` to explain inheritance, integration points, or non-obvious design decisions.

### Function Level

```solidity
/// @notice Deposit liquidity assets in exchange for LP shares
/// @param assets The amount of liquidity assets to deposit
/// @return shares The number of shares minted to the caller
/// @dev Uses ERC-4626 share calculation: shares = assets * totalSupply / totalAssets.
///      Rounds down in favor of the protocol (fewer shares minted).
function deposit(uint256 assets) external returns (uint256 shares) {
```

Required for external/public: `@notice`, all `@param`, all `@return`. Use `@dev` for algorithms, rounding explanations, or important implementation details.

### State Variable Level

```solidity
/// @notice The cumulative total of queued withdrawal assets
uint128 public withdrawsQueued;

/// @notice Mapping of request ID to withdrawal details
mapping(uint256 => WithdrawalRequest) public withdrawalRequests;
```

Document public state variables that are part of the contract's interface. Internal variables need NatSpec only if their purpose isn't obvious from the name.

### Event Level

```solidity
/// @notice Emitted when a user deposits liquidity assets
/// @param owner The address that deposited and received shares
/// @param assets The amount of liquidity assets deposited
/// @param shares The number of shares minted
event Deposit(address indexed owner, uint256 assets, uint256 shares);
```

### Error Level

```solidity
/// @notice Thrown when the requested amount exceeds available balance
/// @param available The current available balance
/// @param required The requested amount
error InsufficientBalance(uint256 available, uint256 required);
```

## File Structure

Order elements within a Solidity file consistently:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// External dependencies (OpenZeppelin, Solmate, etc.)
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// Local imports
import {AbstractARM} from "./AbstractARM.sol";
import {Interfaces} from "./Interfaces.sol";

/// @title ContractName
/// @notice What it does
contract ContractName is AbstractARM {
    using SafeERC20 for IERC20;

    ////////////////////////////////////////////////////
    ///                 TYPE DECLARATIONS
    ////////////////////////////////////////////////////

    struct WithdrawalRequest { ... }
    enum Status { ... }

    ////////////////////////////////////////////////////
    ///                 CONSTANTS
    ////////////////////////////////////////////////////

    uint256 public constant PRICE_SCALE = 1e36;
    uint256 public constant FEE_SCALE = 10_000;

    ////////////////////////////////////////////////////
    ///                 IMMUTABLES
    ////////////////////////////////////////////////////

    IERC20 public immutable token0;
    IERC20 public immutable token1;

    ////////////////////////////////////////////////////
    ///                 STATE VARIABLES
    ////////////////////////////////////////////////////

    uint256 public traderate0;
    uint256 public traderate1;
    mapping(uint256 => WithdrawalRequest) public withdrawalRequests;

    /// @dev Storage gap for upgrade safety
    uint256[50] private __gap;

    ////////////////////////////////////////////////////
    ///                 EVENTS
    ////////////////////////////////////////////////////

    event Deposit(address indexed owner, uint256 assets, uint256 shares);
    event TraderateChanged(uint256 traderate0, uint256 traderate1);

    ////////////////////////////////////////////////////
    ///                 ERRORS
    ////////////////////////////////////////////////////

    error InsufficientBalance(uint256 available, uint256 required);
    error InvalidPrice();

    ////////////////////////////////////////////////////
    ///                 MODIFIERS
    ////////////////////////////////////////////////////

    modifier onlyOwner() { ... }

    ////////////////////////////////////////////////////
    ///                 CONSTRUCTOR
    ////////////////////////////////////////////////////

    constructor(address _token0, address _token1) { ... }

    ////////////////////////////////////////////////////
    ///                 EXTERNAL FUNCTIONS
    ////////////////////////////////////////////////////

    function deposit(uint256 assets) external returns (uint256 shares) { ... }

    ////////////////////////////////////////////////////
    ///                 PUBLIC FUNCTIONS
    ////////////////////////////////////////////////////

    ////////////////////////////////////////////////////
    ///                 INTERNAL FUNCTIONS
    ////////////////////////////////////////////////////

    function _deposit(uint256 assets) internal returns (uint256 shares) { ... }

    ////////////////////////////////////////////////////
    ///                 PRIVATE FUNCTIONS
    ////////////////////////////////////////////////////

    ////////////////////////////////////////////////////
    ///                 VIEW / PURE FUNCTIONS
    ////////////////////////////////////////////////////

    function totalAssets() public view returns (uint256) { ... }
}
```

**Import rules:**
- Always use named imports: `import {X} from "..."`
- Group external deps first, blank line, then local imports
- Alphabetical within each group (optional but preferred)

## Naming Conventions

### Variables

| Type | Convention | Example |
|------|-----------|---------|
| Constants | `UPPER_SNAKE_CASE` | `PRICE_SCALE`, `FEE_SCALE`, `MIN_TOTAL_SUPPLY` |
| Immutables | `camelCase` | `token0`, `liquidityAsset`, `claimDelay` |
| State variables | `camelCase` | `traderate0`, `withdrawsQueued`, `nextWithdrawalIndex` |
| Local variables | `camelCase` | `shares`, `amountOut`, `currentPrice` |
| Function parameters | `_prefixed` when shadowing, otherwise `camelCase` | `_fee`, `assets`, `amount` |
| Private/internal vars | No prefix (ARM convention) | `__gap` for storage gaps only |
| Mappings | Descriptive key→value | `mapping(uint256 => WithdrawalRequest) public withdrawalRequests` |

### Functions

| Type | Convention | Example |
|------|-----------|---------|
| External | `camelCase`, verb-first | `deposit()`, `requestRedeem()`, `claimRedeem()` |
| Internal | `_camelCase` | `_deposit()`, `_swapExactTokensForTokens()` |
| Private | `_camelCase` | `_calculateShares()` |
| View/Pure | `camelCase`, noun or adjective | `totalAssets()`, `convertToShares()` |
| Virtual | Mark `virtual` | `function _externalWithdrawQueue() internal virtual` |
| Override | Mark `override` | `function _externalWithdrawQueue() internal override` |

### Events

- Past tense for completed actions: `Deposited`, `Withdrawn`, `FeeUpdated`
- Present tense for state changes: `TraderateChanged`, `CrossPriceUpdated`
- Index addresses and IDs: `event Deposit(address indexed owner, ...)`

### Errors

- Descriptive name: `InsufficientBalance`, `InvalidPrice`, `ClaimDelayNotMet`
- Include relevant parameters: `error InsufficientBalance(uint256 available, uint256 required)`
- Prefer custom errors over `require` strings (cheaper gas)

### Contracts

- PascalCase: `LidoARM`, `CapManager`, `AbstractARM`
- Abstract prefix for abstract: `AbstractARM`, `Abstract4626MarketWrapper`
- Interface prefix `I`: `IERC20`, `IERC4626`

## Gas Optimization Patterns

### SLOAD Caching

```solidity
// BAD: reads storage 3 times
function bad() external view returns (uint256) {
    if (totalSupply > 0) {
        return balance * SCALE / totalSupply + totalSupply;
    }
    return totalSupply;
}

// GOOD: reads storage once
function good() external view returns (uint256) {
    uint256 _totalSupply = totalSupply;  // cache SLOAD
    if (_totalSupply > 0) {
        return balance * SCALE / _totalSupply + _totalSupply;
    }
    return _totalSupply;
}
```

Cache any storage variable read more than once in a function. Saves ~100 gas per avoided SLOAD (after the first warm read).

### calldata vs memory

```solidity
// BAD: copies array to memory
function bad(uint256[] memory amounts) external { ... }

// GOOD: reads directly from calldata
function good(uint256[] calldata amounts) external { ... }
```

Use `calldata` for external function array/struct parameters that aren't modified. Saves the memory copy cost.

### Unchecked Blocks

```solidity
// Safe: loop counter can't overflow (bounded by array length)
for (uint256 i = 0; i < length;) {
    // ...
    unchecked { ++i; }  // saves ~60 gas per iteration
}

// Safe: we already checked a >= b above
unchecked {
    uint256 diff = a - b;  // can't underflow
}
```

Use `unchecked` only when overflow/underflow is provably impossible. Always add a comment explaining why it's safe.

### Struct Packing

```solidity
// BAD: 3 storage slots (96 bytes, uses 3 slots)
struct Bad {
    uint256 amount;    // slot 0
    address owner;     // slot 1 (20 bytes, wastes 12)
    uint256 timestamp; // slot 2
}

// GOOD: 2 storage slots (64 bytes, uses 2 slots)
struct Good {
    uint256 amount;    // slot 0
    address owner;     // slot 1 (20 bytes)
    uint40 timestamp;  // slot 1 (5 bytes, packs with address)
    bool claimed;      // slot 1 (1 byte, packs with above)
}
```

Pack struct fields to minimize storage slots. Order by size descending within a slot boundary.

### Short-Circuit Evaluation

```solidity
// Put cheap checks first
if (amount == 0 || balanceOf(msg.sender) < amount) revert();

// Put likely-to-fail checks first (saves gas on common revert paths)
if (block.timestamp < deadline || msg.sender != owner) revert();
```

### Prefer Custom Errors

```solidity
// BAD: ~50+ gas overhead for string storage
require(amount > 0, "Amount must be positive");

// GOOD: ~24 gas for selector
error ZeroAmount();
if (amount == 0) revert ZeroAmount();
```

## Testing Standards

### Test Naming

```
test_FunctionName_Description
test_FunctionName_RevertWhen_Condition
test_FunctionName_Fuzz_Description(uint256 amount)
```

Examples:
```solidity
function test_Deposit_SuccessfulDeposit() external { ... }
function test_Deposit_RevertWhen_ZeroAmount() external { ... }
function test_Deposit_RevertWhen_CapExceeded() external { ... }
function test_Deposit_Fuzz_ArbitraryAmounts(uint256 amount) external { ... }
```

### Test Structure

Use modifier-based setup for readable, composable test state:

```solidity
function test_ClaimRedeem_AfterDelay() external
    asUser(alice)
    deposit(alice, 10 ether)
    requestRedeem(alice, 5 ether)
    timejump(CLAIM_DELAY)
{
    uint256 balanceBefore = weth.balanceOf(alice);

    arm.claimRedeem(0);

    assertEq(weth.balanceOf(alice) - balanceBefore, 5 ether, "claim amount");
}
```

### Foundry Cheatcodes

| Cheatcode | Purpose |
|-----------|---------|
| `vm.startPrank(user)` / `vm.stopPrank()` | Set `msg.sender` for next calls |
| `deal(address(token), user, amount)` | Mint tokens to address |
| `vm.warp(timestamp)` | Set `block.timestamp` |
| `vm.roll(blockNumber)` | Set `block.number` |
| `vm.expectRevert(selector)` | Assert next call reverts with error |
| `vm.expectEmit(true, true, false, true)` | Assert event emission |
| `vm.record()` / `vm.accesses()` | Track storage access |
| `stdstore.target(...).sig(...).checked_write(val)` | Direct storage manipulation |
| `makeAddr("name")` | Create labeled address |
| `vm.mockCall(target, data, returnData)` | Mock external call |

### Assertion Patterns

```solidity
// Always include a message for debugging
assertEq(actual, expected, "descriptive message");
assertGt(balance, 0, "balance should be positive");
assertApproxEqAbs(actual, expected, delta, "within tolerance");

// For multiple related assertions, use a descriptive prefix
assertEq(shares, expectedShares, "deposit: shares mismatch");
assertEq(totalAssets, expectedTotal, "deposit: totalAssets mismatch");
```
