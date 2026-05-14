// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Test} from "forge-std/Test.sol";
import {stdStorage, StdStorage} from "forge-std/StdStorage.sol";

import {LidoARM} from "contracts/LidoARM.sol";
import {Proxy} from "contracts/Proxy.sol";
import {IERC20} from "contracts/Interfaces.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";

abstract contract Fork_LidoARM_SwapGasComparison_Base is Test {
    using stdStorage for StdStorage;

    uint256 internal constant FORK_BLOCK = 24_846_066;
    uint256 internal constant PRICE_SCALE = 1e36;
    uint256 internal constant LIQUIDITY_DEPOSIT = 1_000 ether;
    uint256 internal constant SWAP_INPUT = 100 ether;
    uint256 internal constant SWAP_OUTPUT = 100 ether;

    LidoARM internal lidoARM;
    Proxy internal lidoProxy;
    IERC20 internal weth;
    IERC20 internal steth;

    uint256 internal traderate0;
    uint256 internal traderate1;
    uint256 internal amountInEnoughLiquidity;

    function _setUpMainnetForkWithLiquidity() internal {
        vm.createSelectFork(vm.envString("MAINNET_URL"), FORK_BLOCK);

        lidoARM = LidoARM(payable(Mainnet.LIDO_ARM));
        lidoProxy = Proxy(payable(Mainnet.LIDO_ARM));
        weth = IERC20(Mainnet.WETH);
        steth = IERC20(Mainnet.STETH);

        traderate0 = lidoARM.traderate0();
        traderate1 = lidoARM.traderate1();

        deal(address(weth), address(this), LIQUIDITY_DEPOSIT);
        weth.approve(address(lidoARM), LIQUIDITY_DEPOSIT);
        lidoARM.deposit(LIQUIDITY_DEPOSIT);

        amountInEnoughLiquidity = _amountInForDesiredOut(SWAP_OUTPUT);

        _fundSteth(amountInEnoughLiquidity);
        steth.approve(address(lidoARM), amountInEnoughLiquidity);
    }

    function _measureSwap(uint256 amountIn) internal returns (uint256 gasUsed, uint256 amountOut) {
        uint256 gasBefore = gasleft();
        uint256[] memory amounts = lidoARM.swapExactTokensForTokens(steth, weth, amountIn, 0, address(this));
        gasUsed = gasBefore - gasleft();
        amountOut = amounts[1];
    }

    function _amountInForDesiredOut(uint256 desiredOut) internal view returns (uint256) {
        return desiredOut * PRICE_SCALE / traderate1 + 1;
    }

    function _fundSteth(uint256 amount) internal {
        vm.prank(Mainnet.WSTETH);
        steth.transfer(address(this), amount);
    }
}

contract Fork_Concrete_LidoARM_SwapGasCurrentDeployed_Test is Fork_LidoARM_SwapGasComparison_Base {
    function setUp() public {
        _setUpMainnetForkWithLiquidity();
    }

    function test_Gas_CurrentDeployedArm_EnoughLiquidity() public {
        (uint256 gasUsed, uint256 amountOut) = _measureSwap(amountInEnoughLiquidity);

        emit log_named_uint("fork_block", block.number);
        emit log_named_uint("liquidity_deposit_WETH", LIQUIDITY_DEPOSIT);
        emit log_named_uint("amount_in_stETH", amountInEnoughLiquidity);
        emit log_named_uint("amount_out_WETH", amountOut);
        emit log_named_uint("gas_used", gasUsed);
    }

    function test_Gas_CurrentDeployedArm_ExactInput() public {
        (uint256 gasUsed, uint256 amountOut) = _measureSwap(SWAP_INPUT);

        emit log_named_uint("fork_block", block.number);
        emit log_named_uint("liquidity_deposit_WETH", LIQUIDITY_DEPOSIT);
        emit log_named_uint("amount_in_stETH", SWAP_INPUT);
        emit log_named_uint("amount_out_WETH", amountOut);
        emit log_named_uint("gas_used", gasUsed);
    }
}

contract Fork_Concrete_LidoARM_SwapGasUpgraded_Test is Fork_LidoARM_SwapGasComparison_Base {
    function setUp() public {
        _setUpMainnetForkWithLiquidity();
        _upgradeLidoArm();
    }

    function test_Gas_UpgradedArm_EnoughLiquidity() public {
        (uint256 gasUsed, uint256 amountOut) = _measureSwap(amountInEnoughLiquidity);

        emit log_named_uint("fork_block", block.number);
        emit log_named_uint("liquidity_deposit_WETH", LIQUIDITY_DEPOSIT);
        emit log_named_uint("amount_in_stETH", amountInEnoughLiquidity);
        emit log_named_uint("amount_out_WETH", amountOut);
        emit log_named_uint("gas_used", gasUsed);
    }

    function test_Gas_UpgradedArm_ExactInput() public {
        (uint256 gasUsed, uint256 amountOut) = _measureSwap(SWAP_INPUT);

        emit log_named_uint("fork_block", block.number);
        emit log_named_uint("liquidity_deposit_WETH", LIQUIDITY_DEPOSIT);
        emit log_named_uint("amount_in_stETH", SWAP_INPUT);
        emit log_named_uint("amount_out_WETH", amountOut);
        emit log_named_uint("gas_used", gasUsed);
    }

    function _upgradeLidoArm() internal {
        LidoARM upgradedImpl = new LidoARM(
            Mainnet.STETH,
            Mainnet.WETH,
            Mainnet.LIDO_WITHDRAWAL,
            lidoARM.claimDelay(),
            lidoARM.minSharesToRedeem(),
            lidoARM.allocateThreshold()
        );

        vm.prank(lidoProxy.owner());
        lidoProxy.upgradeTo(address(upgradedImpl));

        stdStorage.target(stdstore, address(lidoARM));
        stdStorage.sig(stdstore, lidoARM.reservedWithdrawLiquidity.selector);
        stdStorage.checked_write(stdstore, uint256(0));

        uint256 sellT1 = PRICE_SCALE * PRICE_SCALE / traderate0;

        vm.prank(lidoProxy.owner());
        lidoARM.setPrices(traderate1, sellT1, type(uint256).max, type(uint256).max);
    }
}
