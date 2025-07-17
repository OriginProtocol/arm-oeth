/// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Interfaces
import {SonicHarvester} from "contracts/SonicHarvester.sol";
import {Abstract4626MarketWrapper} from "contracts/markets/Abstract4626MarketWrapper.sol";
import {SiloMarket} from "contracts/markets/SiloMarket.sol";
import {DistributionTypes, SiloIncentivesControllerGaugeLike} from "contracts/Interfaces.sol";

// Test
import {Fork_Shared_Test} from "test/fork/Harvester/shared/Shared.sol";

contract Fork_Concrete_Harvester_Collect_Test_ is Fork_Shared_Test {
    SiloIncentivesControllerGaugeLike public gauge;
    uint256 public constant CAMPAIGN_AMOUNT = 100 ether;
    uint256 public constant AMOUNT_TO_DEPOSIT = 10_000_000 ether;

    function setUp() public virtual override {
        super.setUp();
        gauge = SiloIncentivesControllerGaugeLike(siloMarket.gauge());
    }

    modifier supportStrategy(address strategy) {
        vm.prank(governor);
        harvester.setSupportedStrategy(address(strategy), true);
        _;
    }

    modifier depositInMarket() {
        deal(address(ws), address(originARM), AMOUNT_TO_DEPOSIT);
        vm.startPrank(address(originARM));
        ws.approve(address(siloMarket), AMOUNT_TO_DEPOSIT);
        siloMarket.deposit(AMOUNT_TO_DEPOSIT, address(originARM));
        vm.stopPrank();
        _;
    }

    modifier timejump(uint256 duration) {
        skip(duration);
        _;
    }

    modifier createCampaign() {
        // Get the gauge owner
        address gaugeOwner = gauge.owner();
        // Build the incentives program
        DistributionTypes.IncentivesProgramCreationInput memory input = DistributionTypes.IncentivesProgramCreationInput({
            name: "Origin",
            rewardToken: address(ws),
            emissionPerSecond: uint104(CAMPAIGN_AMOUNT / uint256(1 weeks)),
            distributionEnd: uint40(block.timestamp + 1 weeks)
        });
        // Create the incentives program
        vm.prank(gaugeOwner);
        gauge.createIncentivesProgram(input);
        // Fill the incentives program
        deal(address(ws), address(this), CAMPAIGN_AMOUNT);
        ws.transfer(address(gauge), CAMPAIGN_AMOUNT);
        _;
    }

    function test_RevertWhen_Collect_Because_UnsupportedStrategy() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(siloMarket);
        vm.expectRevert(abi.encodeWithSelector(SonicHarvester.UnsupportedStrategy.selector, address(siloMarket)));
        harvester.collect(tokens);
    }

    function test_Collect_MultipleMarket()
        public
        supportStrategy(address(siloMarket))
        supportStrategy(makeAddr("MockedMarket"))
        depositInMarket
        createCampaign
        timejump(1 weeks)
    {
        uint256 wsBalanceBefore = ws.balanceOf(address(harvester));
        uint256 expectedWs = 0;

        // Create the market list (one real, one mocked)
        address[] memory markets = new address[](2);
        markets[0] = address(siloMarket);
        markets[1] = makeAddr("MockedMarket");
        // Create the mocked market
        address[] memory mockMarketsTokens = new address[](1);
        mockMarketsTokens[0] = makeAddr("MockedToken");
        uint256[] memory mockMarketsAmounts = new uint256[](1);
        mockMarketsAmounts[0] = 123 ether;
        vm.mockCall(
            markets[1],
            abi.encodeWithSelector(Abstract4626MarketWrapper.collectRewards.selector),
            abi.encode(mockMarketsTokens, mockMarketsAmounts)
        );

        // Expected returned values
        address[][] memory expectedTokens = new address[][](2);
        uint256[][] memory expectedAmounts = new uint256[][](2);

        // ---
        // First market
        // ---
        string[] memory names = gauge.getAllProgramsNames();
        expectedTokens[0] = new address[](names.length);
        expectedAmounts[0] = new uint256[](names.length);
        for (uint256 i; i < names.length; i++) {
            (, address _token,,,) = gauge.incentivesPrograms(bytes32(abi.encodePacked(names[i])));
            expectedTokens[0][i] = _token;
            expectedAmounts[0][i] = gauge.getRewardsBalance(address(siloMarket), names[i]);
            if (address(_token) == address(ws)) {
                expectedWs += expectedAmounts[0][i];
            }
        }
        // ---

        // ---
        // Second market
        // ---
        expectedTokens[1] = new address[](1);
        expectedTokens[1][0] = mockMarketsTokens[0];
        expectedAmounts[1] = new uint256[](1);
        expectedAmounts[1][0] = mockMarketsAmounts[0];
        // ---

        // Expect the event
        // There is a not easy behavior:
        // gauge.incentivesPrograms returns address(0) for a program that expired, but when claiming `claim`
        // returns the list of all tokens, even if this is exprired. So I'll try to check emitted event.
        //vm.expectEmit(address(harvester));
        //emit SonicHarvester.RewardsCollected(markets, expectedTokens, expectedAmounts);
        // Main call
        vm.prank(governor);
        (address[][] memory receivedTokens, uint256[][] memory receivedAmounts) = harvester.collect(markets);

        // As we claiming for 2 markets, we should have 2 array of tokens and 2 array of amounts
        assertEq(receivedTokens.length, markets.length, "Invalid tokens length");
        assertEq(receivedAmounts.length, markets.length, "Invalid amounts length");

        // Check received tokens and amounts
        for (uint256 i; i < markets.length; i++) {
            uint256 len = receivedTokens[i].length;
            for (uint256 j; j < len; j++) {
                if (expectedTokens[i][j] != address(0)) {
                    assertEq(receivedTokens[i][j], expectedTokens[i][j], "Invalid token");
                }
                assertEq(receivedAmounts[i][j], expectedAmounts[i][j], "Invalid amount");
            }
        }
        // Check the balance of the harvester
        assertEq(ws.balanceOf(address(harvester)) - wsBalanceBefore, expectedWs, "Invalid amount on harvester");
    }
}
