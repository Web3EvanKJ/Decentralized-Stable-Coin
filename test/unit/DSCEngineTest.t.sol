// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import "forge-std/console.sol";


contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig config;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;

    address public user = makeAddr("user");
    address public liquidator = makeAddr("liquidator");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant AMOUNT_REDEEM = 1 ether;
    uint256 public constant DSC_MINTED = 15e18;
    uint256 public constant AMOUNT_BURN = 5e18;

    uint256 amountToMint = 100 ether;
    uint256 public collateralToCover = 20 ether;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (ethUsdPriceFeed,btcUsdPriceFeed , weth, ,) = config.activeNetworkConfig();
    }

    //////////////////////
    // Constructor Tests /
    //////////////////////
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertsIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceMustBeTheSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    ////////////////
    // Price Tests /
    ////////////////

    function testGetUsdValue() public {
        uint256 ethAmount = 15e18;
        // 15e18 * 2000/ETH = 30,000e18; 
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = dsce.getUsdValue(weth, ethAmount);
        assertEq(actualUsd, expectedUsd);
    }

    function testGetTokenAmountFromUsd() public {
        uint256 usdAmount = 100 ether;
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = dsce.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }

    ///////////////////
    // mintDsc Tests /
    //////////////////

    function dscMintedIncreaseAfterMintDsc() public {
        (uint256 totalDscMinted,) = dsce.getAccountInformation(user);

        deal(address(weth), user, 10000e18);
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        dsce.mintDsc(DSC_MINTED);
        vm.stopPrank();

        (uint256 expectedTotalDscMinted,) = dsce.getAccountInformation(user);

        assertEq(expectedTotalDscMinted, totalDscMinted + DSC_MINTED);
    }

    /////////////////////////////////
    // redeemCollateralForDsc Tests /
    /////////////////////////////////

    modifier userDepositCollateralAndMintDsc() {
        deal(address(weth), user, 10000e18);
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, DSC_MINTED);
        vm.stopPrank();
        _;
    }

    function testDSCBurnedAndRedeemed() public userDepositCollateralAndMintDsc {

        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(user);

        vm.startPrank(user);
        dsc.approve(address(dsce), DSC_MINTED);
        dsce.redeemCollateralForDsc(weth, AMOUNT_COLLATERAL, DSC_MINTED);
        vm.stopPrank();

        uint256 collateralInUsd = dsce.getUsdValue(weth, AMOUNT_COLLATERAL);

        (uint256 expectedTotalDscMinted, uint256 expectedCollateralValueInUsd ) = dsce.getAccountInformation(user);
        assertEq(totalDscMinted - DSC_MINTED, expectedTotalDscMinted);
        assertEq(collateralValueInUsd - collateralInUsd, expectedCollateralValueInUsd);
    }

    //////////////////
    // burnDsc Tests /
    //////////////////

    function testBurnDsc() public  userDepositCollateralAndMintDsc {
        (uint256 totalDscMinted, ) = dsce.getAccountInformation(user);

        vm.startPrank(user);
        dsc.approve(address(dsce), AMOUNT_BURN);
        dsce.burnDsc(AMOUNT_BURN);
        vm.stopPrank();

        (uint256 expectedTotalDscMinted, ) = dsce.getAccountInformation(user);
        assertEq(totalDscMinted - AMOUNT_BURN, expectedTotalDscMinted);
    }

    ////////////////////////////
    // redeemCollateral Tests /
    ///////////////////////////

    function testRedeemCollateral() public userDepositCollateralAndMintDsc {
        (, uint256 collateralValueInUsd) = dsce.getAccountInformation(user);

        vm.startPrank(user);
        dsc.approve(address(dsce), DSC_MINTED);
        dsce.redeemCollateral(weth, AMOUNT_REDEEM);
        vm.stopPrank();

        uint256 collateralInUsd = dsce.getUsdValue(weth, AMOUNT_REDEEM);
        (, uint256 expectedCollateralValueInUsd ) = dsce.getAccountInformation(user);

        assertEq(collateralValueInUsd - collateralInUsd, expectedCollateralValueInUsd);
    }

    function testRedeemRevertWhenDepositAndRedeemSameAmount() public userDepositCollateralAndMintDsc {
        vm.startPrank(user);
        dsc.approve(address(dsce), DSC_MINTED);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, 0));
        dsce.redeemCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    //////////////////////////////////////
    // depositCollateralAndMintDsc Tests /
    //////////////////////////////////////

    function testCallDepositCollateralAndMintDscFunction() public userDepositCollateralAndMintDsc {

        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(user);

        uint256 expectedDepositAmount = dsce.getTokenAmountFromUsd(weth, collateralValueInUsd);
        assertEq(totalDscMinted, DSC_MINTED);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
    }

    ////////////////////////////
    // depositCollateral Tests /
    ////////////////////////////

    function testRevertsIfCollateralZero() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock ranToken = new ERC20Mock();
        vm.startPrank(user);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        dsce.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        deal(address(weth), user, 10000e18);
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(user);

        uint256 expectedTotalDscMinted = 0;
        uint256 expectedDepositAmount = dsce.getTokenAmountFromUsd(weth, collateralValueInUsd);
        assertEq(totalDscMinted, expectedTotalDscMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
    }

    ////////////////////
    // liquidate Tests /
    ////////////////////

        modifier liquidated() {
        deal(address(weth), user, 10000e18);
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, amountToMint);
        vm.stopPrank();
        int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18

        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);
        uint256 userHealthFactor = dsce.getHealthFactor(user);

        ERC20Mock(weth).mint(liquidator, collateralToCover);

        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(dsce), collateralToCover);
        dsce.depositCollateralAndMintDsc(weth, collateralToCover, amountToMint);
        dsc.approve(address(dsce), amountToMint);
        dsce.liquidate(weth, user, amountToMint); // We are covering their whole debt
        vm.stopPrank();
        _;
    }
    
    function testLiquidationPayoutIsCorrect() public liquidated {
        uint256 liquidatorWethBalance = ERC20Mock(weth).balanceOf(liquidator);
        console.log(dsce.getTokenAmountFromUsd(weth, amountToMint));
        uint256 expectedWeth = dsce.getTokenAmountFromUsd(weth, amountToMint)
            + (dsce.getTokenAmountFromUsd(weth, amountToMint) / dsce.getLiquidationBonus());
        uint256 hardCodedExpected = 6111111111111111110;
        assertEq(liquidatorWethBalance, hardCodedExpected);
        assertEq(liquidatorWethBalance, expectedWeth);
    }   
}