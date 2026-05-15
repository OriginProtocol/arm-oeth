// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Test} from "forge-std/Test.sol";

import {CapManager} from "contracts/CapManager.sol";
import {IERC20} from "contracts/Interfaces.sol";
import {LidoARM} from "contracts/LidoARM.sol";
import {Proxy} from "contracts/Proxy.sol";
import {StETHAssetAdapter} from "contracts/adapters/StETHAssetAdapter.sol";
import {WstETHAssetAdapter} from "contracts/adapters/WstETHAssetAdapter.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";

contract Fork_Concrete_LidoARM_SwapGasClean_Test is Test {
    uint256 internal constant FORK_BLOCK = 24_846_066;
    uint256 internal constant BUY_PRICE = 9995e32; // 0.9995 WETH per stETH
    uint256 internal constant SELL_PRICE = 1001e33; // 1.001 WETH per stETH
    uint256 internal constant SWAP_AMOUNT = 100 ether;
    uint256 internal constant ARM_BALANCE = 1_000 ether;
    uint256 internal constant SWAP_FEE = 1; // 1 bp

    LidoARM internal lidoARM;
    IERC20 internal weth;
    IERC20 internal steth;

    address internal feeCollector = makeAddr("feeCollector");
    address internal operator = makeAddr("operator");

    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_URL"), FORK_BLOCK);

        weth = IERC20(Mainnet.WETH);
        steth = IERC20(Mainnet.STETH);

        Proxy capManagerProxy = new Proxy();
        Proxy lidoProxy = new Proxy();

        CapManager capManagerImpl = new CapManager(address(lidoProxy));
        capManagerProxy.initialize(
            address(capManagerImpl), address(this), abi.encodeWithSignature("initialize(address)", operator)
        );

        LidoARM lidoImpl = new LidoARM(Mainnet.WETH, 10 minutes, 0, 0);

        deal(address(weth), address(this), 1e12);
        weth.approve(address(lidoProxy), type(uint256).max);

        lidoProxy.initialize(
            address(lidoImpl),
            address(this),
            abi.encodeWithSignature(
                "initialize(string,string,address,uint256,address,address)",
                "Lido ARM",
                "ARM-ST",
                operator,
                SWAP_FEE,
                feeCollector,
                address(capManagerProxy)
            )
        );

        lidoARM = LidoARM(payable(address(lidoProxy)));
        address stethAdapter =
            address(new StETHAssetAdapter(address(lidoProxy), address(weth), address(steth), Mainnet.LIDO_WITHDRAWAL));
        address wstethAdapter = address(
            new WstETHAssetAdapter(
                address(lidoProxy), address(weth), address(steth), Mainnet.WSTETH, Mainnet.LIDO_WITHDRAWAL
            )
        );
        lidoARM.addBaseAsset(
            address(steth),
            stethAdapter,
            BUY_PRICE,
            SELL_PRICE,
            type(uint128).max,
            type(uint128).max,
            PRICE_SCALE(),
            true
        );
        lidoARM.addBaseAsset(
            Mainnet.WSTETH,
            wstethAdapter,
            BUY_PRICE,
            SELL_PRICE,
            type(uint128).max,
            type(uint128).max,
            PRICE_SCALE(),
            false
        );
        lidoARM.setPrices(address(steth), BUY_PRICE, SELL_PRICE, type(uint128).max, type(uint128).max);

        deal(address(weth), address(lidoARM), ARM_BALANCE);
        _fundSteth(address(lidoARM), ARM_BALANCE);
        deal(address(weth), address(this), SWAP_AMOUNT);
        _fundSteth(address(this), SWAP_AMOUNT);

        weth.approve(address(lidoARM), type(uint256).max);
        steth.approve(address(lidoARM), type(uint256).max);
    }

    function test_Gas_Clean_SwapExact_StethToWeth_FeePath() public {
        (uint256 gasUsed, uint256 amountOut) = _measureSwap(steth, weth, SWAP_AMOUNT);

        emit log_named_uint("fork_block", block.number);
        emit log_named_uint("swap_fee_bps", lidoARM.fee());
        emit log_named_uint("amount_in_stETH", SWAP_AMOUNT);
        emit log_named_uint("amount_out_WETH", amountOut);
        emit log_named_uint("gas_used", gasUsed);
    }

    function test_Gas_Clean_SwapExact_WethToSteth_NoFeePath() public {
        (uint256 gasUsed, uint256 amountOut) = _measureSwap(weth, steth, SWAP_AMOUNT);

        emit log_named_uint("fork_block", block.number);
        emit log_named_uint("swap_fee_bps", lidoARM.fee());
        emit log_named_uint("amount_in_WETH", SWAP_AMOUNT);
        emit log_named_uint("amount_out_stETH", amountOut);
        emit log_named_uint("gas_used", gasUsed);
    }

    function _measureSwap(IERC20 inToken, IERC20 outToken, uint256 amountIn)
        internal
        returns (uint256 gasUsed, uint256 amountOut)
    {
        uint256 gasBefore = gasleft();
        uint256[] memory amounts = lidoARM.swapExactTokensForTokens(inToken, outToken, amountIn, 0, address(this));
        gasUsed = gasBefore - gasleft();
        amountOut = amounts[1];
    }

    function _fundSteth(address to, uint256 amount) internal {
        vm.prank(Mainnet.WSTETH);
        steth.transfer(to, amount);
    }

    function PRICE_SCALE() internal pure returns (uint256) {
        return 1e36;
    }
}
