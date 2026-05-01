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

    string private checkpointLabel;
    uint256 private checkpointGasLeft = 1; // Start the slot warm.
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
        // to toggle if the gas measurement includes the upgrade or not, comment out the next line to measure the current deployed ARM vs the upgraded ARM.
        //_upgradeLidoArm();

    }

    function startMeasuringGas(string memory label) internal virtual {
        checkpointLabel = label;

        checkpointGasLeft = gasleft();
    }

    function stopMeasuringGas() internal virtual {
        uint256 checkpointGasLeft2 = gasleft();

        // Subtract 100 to account for the warm SLOAD in startMeasuringGas.
        uint256 gasDelta = checkpointGasLeft - checkpointGasLeft2 - 100;

        emit log_named_uint(string(abi.encodePacked(checkpointLabel, " Gas")), gasDelta);
    }

    function test_Gas_UpgradedArm_EnoughLiquidity() public {
        _measureSwap("UpgradedArm_EnoughLiquidity", amountInEnoughLiquidity);
    }

    function test_Gas_CurrentDeployedArm_EnoughLiquidity() public {
        _measureSwap("CurrentDeployedArm_EnoughLiquidity", amountInEnoughLiquidity);
    }

    function test_Gas_UpgradedArm_NeedsMarketLiquidity() public {
        _measureSwap("UpgradedArm_NeedsMarketLiquidity", amountInNeedsMarketLiquidity);
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

        // The new impl introduces buy/sell liquidity caps that default to 0; refresh them
        // by re-applying the current traderates so swaps below aren't blocked.
        uint256 buyT1 = lidoARM.traderate1();
        uint256 sellT1 = PRICE_SCALE * PRICE_SCALE / lidoARM.traderate0();
        vm.startPrank(lidoARM.owner());
        lidoARM.setFee(1e10);
        lidoARM.setPrices(buyT1, sellT1, type(uint256).max, type(uint256).max);
        vm.stopPrank();
    }

    function _measureSwap(string memory label, uint256 amountIn) internal {
        startMeasuringGas(label);
        lidoARM.swapExactTokensForTokens(steth, weth, amountIn, 0, address(this));
        stopMeasuringGas();
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
