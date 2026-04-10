// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Test} from "forge-std/Test.sol";

import {LidoARM} from "contracts/LidoARM.sol";
import {Proxy} from "contracts/Proxy.sol";
import {IERC20} from "contracts/Interfaces.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";

contract Fork_Concrete_LidoARM_SwapGasComparison_Test is Test {
    uint256 internal constant FORK_BLOCK = 24_846_066;
    uint256 internal constant PRICE_SCALE = 1e36;

    LidoARM internal lidoARM;
    Proxy internal lidoProxy;
    IERC20 internal weth;
    IERC20 internal steth;

    uint256 internal reserveWeth;
    uint256 internal traderate1;
    address internal activeMarket;
    uint256 internal marketLiquidity;
    uint256 internal amountInEnoughLiquidity;
    uint256 internal amountInNeedsMarketLiquidity;

    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_URL"), FORK_BLOCK);

        lidoARM = LidoARM(payable(Mainnet.LIDO_ARM));
        lidoProxy = Proxy(payable(Mainnet.LIDO_ARM));
        weth = IERC20(Mainnet.WETH);
        steth = IERC20(Mainnet.STETH);

        (reserveWeth,) = lidoARM.getReserves();
        traderate1 = lidoARM.traderate1();
        activeMarket = lidoARM.activeMarket();
        marketLiquidity = IERC4626(activeMarket).maxWithdraw(address(lidoARM));

        require(activeMarket != address(0), "missing active market");
        require(reserveWeth > 0, "missing ARM liquidity");
        require(marketLiquidity > 0, "missing market liquidity");

        amountInEnoughLiquidity = _amountInForDesiredOut(reserveWeth / 10);
        amountInNeedsMarketLiquidity = _amountInForDesiredOut(reserveWeth + _marketShortfallTarget());

        _fundSteth(amountInNeedsMarketLiquidity);
        steth.approve(address(lidoARM), type(uint256).max);
    }

    function test_Gas_UpgradedArm_EnoughLiquidity_FeatureDisabled() public {
        _upgradeLidoArm(false);

        (uint256 gasUsed, uint256 amountOut) = _measureSwap(amountInEnoughLiquidity);

        emit log_named_uint("fork_block", block.number);
        emit log_named_uint("amount_in_stETH", amountInEnoughLiquidity);
        emit log_named_uint("amount_out_WETH", amountOut);
        emit log_named_uint("gas_used", gasUsed);
    }

    function test_Gas_UpgradedArm_EnoughLiquidity_FeatureEnabled() public {
        _upgradeLidoArm(true);

        (uint256 gasUsed, uint256 amountOut) = _measureSwap(amountInEnoughLiquidity);

        emit log_named_uint("fork_block", block.number);
        emit log_named_uint("amount_in_stETH", amountInEnoughLiquidity);
        emit log_named_uint("amount_out_WETH", amountOut);
        emit log_named_uint("gas_used", gasUsed);
    }

    function test_Gas_CurrentDeployedArm_EnoughLiquidity() public {
        (uint256 gasUsed, uint256 amountOut) = _measureSwap(amountInEnoughLiquidity);

        emit log_named_uint("fork_block", block.number);
        emit log_named_uint("amount_in_stETH", amountInEnoughLiquidity);
        emit log_named_uint("amount_out_WETH", amountOut);
        emit log_named_uint("gas_used", gasUsed);
    }

    function test_Gas_UpgradedArm_NeedsMarketLiquidity() public {
        _upgradeLidoArm(true);

        uint256 reserveBefore = reserveWeth;
        (uint256 gasUsed, uint256 amountOut) = _measureSwap(amountInNeedsMarketLiquidity);

        require(amountOut > reserveBefore, "swap did not need market liquidity");

        emit log_named_uint("fork_block", block.number);
        emit log_named_uint("amount_in_stETH", amountInNeedsMarketLiquidity);
        emit log_named_uint("amount_out_WETH", amountOut);
        emit log_named_uint("weth_reserve_before", reserveBefore);
        emit log_named_uint("market_shortfall", amountOut - reserveBefore);
        emit log_named_uint("gas_used", gasUsed);
    }

    function _upgradeLidoArm(bool withdrawFromMarketOnSwap) internal {
        LidoARM upgradedImpl = new LidoARM(
            Mainnet.STETH,
            Mainnet.WETH,
            Mainnet.LIDO_WITHDRAWAL,
            lidoARM.claimDelay(),
            lidoARM.minSharesToRedeem(),
            lidoARM.allocateThreshold(),
            withdrawFromMarketOnSwap
        );

        vm.prank(lidoProxy.owner());
        lidoProxy.upgradeTo(address(upgradedImpl));
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

    function _marketShortfallTarget() internal view returns (uint256 shortfall) {
        shortfall = marketLiquidity / 100;
        if (shortfall > 25 ether) shortfall = 25 ether;
        if (shortfall == 0) shortfall = 1 ether;
        require(shortfall < marketLiquidity, "insufficient market liquidity");
    }

    function _fundSteth(uint256 amount) internal {
        vm.prank(Mainnet.WSTETH);
        steth.transfer(address(this), amount);
    }
}
