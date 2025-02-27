// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IRugRumble} from "../../src/interfaces/IRugRumble.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import "../dex-adapters/MockUniswapV2Adapter.sol";
import {MockERC20} from "../utils/MockERC20.sol";
import {Vault} from "../../src/Vault.sol";
import "./MockRugRumble.sol";
import "forge-std/Test.sol";

contract VaultTest is Test {
    bytes32 public constant EPOCH_CONTROLLER_ROLE = keccak256("EPOCH_CONTROLLER_ROLE");
    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");

    Vault vault;
    MockRugRumble gameContract;
    MockUniswapV2Adapter dexAdapter;
    MockERC20 tokenA;
    MockERC20 tokenB;
    address defaultAdmin = address(1);
    address rugRumbleOwner = address(2);
    address owner = address(3);
    address supportedToken = address(4);
    address newToken = address(5);
    address epochController = address(6);
    address protocolFeeReceiver = address(7);
    address player1 = address(9);
    address player2 = address(10);
    address player3 = address(11);
    address player4 = address(12);

    function setUp() public {
        gameContract = new MockRugRumble();
        dexAdapter = new MockUniswapV2Adapter(200);
        tokenA = new MockERC20("Token A", "TKA");
        tokenB = new MockERC20("Token B", "TKB");
        // Deploy the Vault contract address;
        address[] memory initialSupportedTokens = new address[](1);
        initialSupportedTokens[0] = supportedToken;
        vault = new Vault(address(gameContract), initialSupportedTokens, defaultAdmin);
        // Set up roles
        vm.prank(defaultAdmin);
        vault.grantRole(OWNER_ROLE, owner);
        vm.prank(defaultAdmin);
        vault.grantRole(EPOCH_CONTROLLER_ROLE, epochController);
    }

    // TEST CASES FOR addSupportedToken
    function testAddSupportedToken_Success() public {
        // Verify that the TokenAdded event is emitted
        vm.expectEmit(true, true, false, false);
        emit IVault.TokenAdded(newToken, owner);
        vm.prank(owner);
        vault.addSupportedToken(newToken);

        // Verify that the token is added
        bool isSupported = vault.supportedTokens(newToken);
        assertTrue(isSupported);
    }

    function testAddSupportedToken_AlreadySupported() public {
        // Add the same token again as the owner
        vm.prank(owner);
        vm.expectRevert("Token already supported");
        vault.addSupportedToken(supportedToken);
    }

    // TEST CASES FOR setDexAdapter
    function testSetDexAdapter_Success() public {
        vm.prank(owner);
        vault.setDexAdapter(address(tokenA), address(tokenB), address(dexAdapter));

        // Verify that the DEX adapter is set correctly
        bytes32 pairHash = keccak256(abi.encodePacked(address(tokenA), address(tokenB)));
        bytes32 reversePairHash = keccak256(abi.encodePacked(address(tokenB), address(tokenA)));

        assertEq(vault.dexAdapters(pairHash), address(dexAdapter));
        assertEq(vault.dexAdapters(reversePairHash), address(dexAdapter));
    }

    function testSetDexAdapter_InvalidTokenAddress() public {
        vm.prank(owner);
        vm.expectRevert("Invalid token address");
        vault.setDexAdapter(address(0), address(tokenB), address(dexAdapter));

        vm.prank(owner);
        vm.expectRevert("Invalid token address");
        vault.setDexAdapter(address(tokenA), address(0), address(dexAdapter));
    }

    function testSetDexAdapter_InvalidDexAdapterAddress() public {
        vm.prank(owner);
        vm.expectRevert("Invalid DEX adapter address");
        vault.setDexAdapter(address(tokenA), address(tokenB), address(0));
    }

    function testSetDexAdapter_WithoutOwnerRole() public {
        address nonOwner = address(10);

        vm.prank(nonOwner);
        vm.expectRevert(); // Should revert due to missing OWNER_ROLE
        vault.setDexAdapter(address(tokenA), address(tokenB), address(dexAdapter));
    }

    function testStartEpoch_Success() public {
        address [] memory tokenAddresses = new address[](2);
        tokenAddresses[0] = supportedToken;
        tokenAddresses[1] = newToken;

        // Add the newToken to the supported tokens before starting the epoch
        vm.prank(owner);
        vault.addSupportedToken(newToken);

        // Expect the EpochStarted event to be emitted
        vm.expectEmit(true, true, true, true);
        emit IVault.EpochStarted(1, tokenAddresses);

        // Start the epoch
        vm.prank(epochController);
        vault.startEpoch(tokenAddresses);

        // Verify the epoch was started correctly
        IVault.Epoch memory epoch = vault.getEpoch(1);
        assertEq(epoch.epochId, 1);
        assertEq(uint(epoch.state), uint(IVault.EpochState.STARTED));
        assertEq(epoch.supportedTokens.length, 2);
        assertEq(epoch.supportedTokens[0], supportedToken);
        assertEq(epoch.supportedTokens[1], newToken);
    }

    function testStartEpoch_TokenNotSupported() public {
        address[] memory tokenAddresses = new address[](1);
        tokenAddresses[0] = newToken; // newToken is not supported

        vm.prank(epochController);
        vm.expectRevert("Token is not supported by vault");
        vault.startEpoch(tokenAddresses);
    }

    function testStartEpoch_WithoutEpochControllerRole() public {
        address[] memory tokenAddresses = new address[](1);
        tokenAddresses[0] = supportedToken;

        address nonEpochController = address(10);
        vm.prank(nonEpochController);
        vm.expectRevert();
        vault.startEpoch(tokenAddresses);
    }

    function testEndEpoch_Success() public {
        address[] memory tokenAddresses = new address[](1);
        tokenAddresses[0] = supportedToken;

        // Start an epoch first
        vm.prank(epochController);
        vault.startEpoch(tokenAddresses);

        // Expect the EpochFinished event to be emitted
        vm.expectEmit(true, true, true, true);
        emit IVault.EpochFinished(1);

        // End the epoch
        vm.prank(epochController);
        vault.endEpoch(1);

        // Verify the epoch was ended correctly
        IVault.Epoch memory epoch = vault.getEpoch(1);
        assertEq(uint(epoch.state), uint(IVault.EpochState.FINISHED));
    }

    function testEndEpoch_EpochNotStarted() public {
        // Attempt to end an epoch that was not started
        vm.prank(epochController);
        vm.expectRevert("Epoch is not started");
        vault.endEpoch(1);
    }

    function testEndEpoch_WithoutEpochControllerRole() public {
        address[] memory tokenAddresses = new address[](1);
        tokenAddresses[0] = supportedToken;

        // Start an epoch first
        vm.prank(epochController);
        vault.startEpoch(tokenAddresses);

        // Attempt to end the epoch without the EPOCH_CONTROLLER_ROLE
        address nonEpochController = address(10);
        vm.prank(nonEpochController);
        vm.expectRevert();
        vault.endEpoch(1);
    }

    function testDepositFromGame_Success() public {
        uint256 depositAmountA = 100;
        uint256 gameId = 1;
        uint256 epochId = 1;
        // Start an epoch
        address [] memory tokenAddresses = new address[](2);
        tokenAddresses[0] = address(tokenA);
        tokenAddresses[1] = address(tokenB);
        
        vm.prank(owner);
        vault.addSupportedToken(address(tokenA));

        vm.prank(owner);
        vault.addSupportedToken(address(tokenB));

        vm.prank(epochController);
        vault.startEpoch(tokenAddresses);

        // Approve the Vault contract to transfer tokens on behalf of the game contract
        tokenA.mint(address(gameContract), depositAmountA);
        vm.prank(address(gameContract));
        tokenA.approve(address(vault), depositAmountA);

        // Deposit from the game contract
        vm.prank(address(gameContract));
        vault.depositFromGame(epochId, gameId, address(tokenA), depositAmountA);

        // Verify that the deposit is recorded
        uint256 recordedDeposit = vault.epochDeposits(epochId, address(tokenA));
        assertEq(recordedDeposit, depositAmountA);

        // Verify that the game ID is recorded
        uint256[] memory games = vault.getEpochGames(epochId);
        assertEq(games.length, 1);
        assertEq(games[0], gameId);
    }

    function testDepositFromGame_EpochNotStarted() public {
        uint256 depositAmountA = 100;
        uint256 gameId = 1;
        uint256 epochId = 1;

        // Approve the Vault contract to transfer tokens on behalf of the game contract
        tokenA.mint(address(gameContract), depositAmountA);
        vm.prank(address(gameContract));
        tokenA.approve(address(vault), depositAmountA);

        // Attempt to deposit before the epoch is started
        vm.prank(address(gameContract));
        vm.expectRevert("Epoch is not started");
        vault.depositFromGame(epochId, gameId, address(tokenA), depositAmountA);
    }

    function testDepositFromGame_TokenNotSupported() public {
        uint256 depositAmountA = 100;
        uint256 gameId = 1;
        uint256 epochId = 1;

        // Start an epoch
        address[] memory tokenAddresses = new address[](1);
        tokenAddresses[0] = address(tokenA);

        vm.prank(owner);
        vault.addSupportedToken(address(tokenA));

        vm.prank(epochController);
        vault.startEpoch(tokenAddresses);

        // Attempt to deposit with an unsupported token
        vm.prank(owner);
        MockERC20 unsupportedToken = new MockERC20("Unsupported Token", "UTK");
        unsupportedToken.mint(address(gameContract), depositAmountA);

        vm.prank(address(gameContract));
        unsupportedToken.approve(address(vault), depositAmountA);

        vm.prank(address(gameContract));
        vm.expectRevert("Token not supported");
        vault.depositFromGame(epochId, gameId, address(unsupportedToken), depositAmountA);
    }

    function testDepositFromGame_TokenTransferFailed() public {
        uint256 depositAmountA = 100;
        uint256 gameId = 1;
        uint256 epochId = 1;

        // Start an epoch
        address[] memory tokenAddresses = new address[](1);
        tokenAddresses[0] = address(tokenA);

        vm.prank(owner);
        vault.addSupportedToken(address(tokenA));

        vm.prank(epochController);
        vault.startEpoch(tokenAddresses);

        // Mint tokens but do not approve the Vault contract
        tokenA.mint(address(gameContract), depositAmountA);

        // Attempt to deposit without approval
        vm.prank(address(gameContract));
        vm.expectRevert();
        vault.depositFromGame(epochId, gameId, address(tokenA), depositAmountA);
    }

    function testDepositFromGame_WithoutGameContractRole() public {
        uint256 depositAmountA = 100;
        uint256 gameId = 1;
        uint256 epochId = 1;

        // Start an epoch
        address[] memory tokenAddresses = new address[](1);
        tokenAddresses[0] = address(tokenA);

        vm.prank(owner);
        vault.addSupportedToken(address(tokenA));

        vm.prank(epochController);
        vault.startEpoch(tokenAddresses);

        // Approve the Vault contract to transfer tokens on behalf of the game contract
        tokenA.mint(address(gameContract), depositAmountA);
        vm.prank(address(gameContract));
        tokenA.approve(address(vault), depositAmountA);

        // Attempt to deposit without the GAME_CONTRACT_ROLE
        address nonGameContract = address(10);
        vm.prank(nonGameContract);
        vm.expectRevert();
        vault.depositFromGame(epochId, gameId, address(tokenA), depositAmountA);
    }

    // Helper Methods to enforce code reusability
    function setupAndStartEpoch(uint256 tokenOutputAmount) internal {
        // Set up and start an epoch with tokenA and tokenB
        address[] memory tokenAddresses = new address[](2);
        tokenAddresses[0] = address(tokenA);
        tokenAddresses[1] = address(tokenB);

        MockUniswapV2Adapter _dexAdapter = new MockUniswapV2Adapter(tokenOutputAmount);
        vm.prank(owner);
        vault.addSupportedToken(address(tokenA));
        vm.prank(owner);
        vault.addSupportedToken(address(tokenB));

        vm.prank(owner);
        vault.setDexAdapter(address(tokenA), address(tokenB), address(_dexAdapter));
        vm.prank(epochController);
        vault.startEpoch(tokenAddresses);
    }

    function setupGame(
        uint256 gameId,
        address tokenAddressA,
        address tokenAddressB,
        uint256 depositAmountA, 
        uint256 depositAmountB,
        address playerA,
        address playerB,
        address winner,
        address looser,
        uint256 epochId) internal {
        // Set up the mock game data and deposit tokens for the game
        gameContract.setMockGame(gameId, playerA, playerB, tokenAddressA, tokenAddressB, depositAmountA, depositAmountB, winner, looser, epochId);
    }

    function depositFromGame(uint256 depositAmount, uint256 gameId, uint256 epochId, MockERC20 token) internal {
        token.mint(address(gameContract), depositAmount);
        vm.prank(address(gameContract));
        token.approve(address(vault), depositAmount);
        vm.prank(address(gameContract));
        vault.depositFromGame(epochId, gameId, address(token), depositAmount);
    }

    function finishEpoch(uint256 epochId) internal {
        // Finish the epoch
        vm.prank(epochController);
        vault.endEpoch(epochId);
    }

    function testSettleVault_Success() public {
        uint256 depositAmountA = 100;
        uint256 depositAmountB = 200;
        uint256 gameId = 1;
        uint256 epochId = 1;
        bytes memory swapData = abi.encode(uint24(3000), address(0));
        uint24 tokenOutputAmount = 200;
        setupAndStartEpoch(tokenOutputAmount);

        setupGame(gameId, address(tokenA), address(tokenB), depositAmountA, depositAmountB, player1, player2, player1, player2, epochId);
        depositFromGame(depositAmountA, gameId, epochId, tokenA);
        depositFromGame(depositAmountB, gameId, epochId, tokenB);
        finishEpoch(epochId);

        // Expect the VaultSettled event to be emitted
        vm.expectEmit(true, true, true, true);
        emit IVault.VaultSettled(epochId, address(tokenA), depositAmountA+tokenOutputAmount);

        vm.prank(epochController);
        vault.settleVault(swapData, address(tokenA), epochId);
        // Get player1 balance and verify the balance to be equal to depositAmountA
        uint256 player1Balance = tokenA.balanceOf(player1);
        assertEq(player1Balance, depositAmountA+tokenOutputAmount);
    }

    function testSettleVault_SuccessSimpleTokenDistribution() public {
        uint256 depositAmountA = 100;
        uint256 depositAmountB = 200;
        uint256 gameId = 1;
        uint256 gameId2 = 2;
        uint256 epochId = 1;
        bytes memory swapData = abi.encode(uint24(3000), address(0));
        uint256 tokenOutputAmount = 300;
        setupAndStartEpoch(tokenOutputAmount);

        setupGame(gameId, address(tokenA), address(tokenB), depositAmountA, depositAmountB, player1, player2, player1, player2, epochId);
        setupGame(gameId2, address(tokenA), address(tokenB), depositAmountA, depositAmountB, player3, player4, player3, player4, epochId);
        depositFromGame(depositAmountA, gameId, epochId, tokenA);
        depositFromGame(depositAmountB, gameId2, epochId, tokenB);

        finishEpoch(epochId);

        // Expect the VaultSettled event to be emitted
        vm.expectEmit(true, true, true, true);
        emit IVault.VaultSettled(epochId, address(tokenA), depositAmountA+tokenOutputAmount);

        vm.prank(epochController);
        vault.settleVault(swapData, address(tokenA), epochId);

        // assert player1 tokenA balance is 150 and player2 tokenA balance is 150
        uint256 player1Balance = tokenA.balanceOf(player1);
        uint256 player3Balance = tokenA.balanceOf(player3);
        assertEq(player1Balance, (depositAmountA+tokenOutputAmount)/2);
        assertEq(player3Balance, (depositAmountA+tokenOutputAmount)/2);
    }

    function testSettleVault_SuccessComplexTokenDistribution() public {
        uint256 depositAmountA = 133;
        uint256 depositAmountB = 459;
        uint256 gameId = 1;
        uint256 gameId2 = 2;
        uint256 epochId = 1;
        bytes memory swapData = abi.encode(uint24(3000), address(0));
        uint256 tokenOutputAmount = 294;
        setupAndStartEpoch(tokenOutputAmount);

        setupGame(gameId, address(tokenA), address(tokenB), depositAmountA, depositAmountB, player1, player2, player1, player2, epochId);
        setupGame(gameId2, address(tokenA), address(tokenB), depositAmountA, depositAmountB, player3, player4, player3, player4, epochId);
        depositFromGame(depositAmountA, gameId, epochId, tokenA);
        depositFromGame(depositAmountB, gameId2, epochId, tokenB);

        finishEpoch(epochId);

        // Calculate the expected total amount of winning tokens after swaps
        uint256 expectedWinningTokenBalance = depositAmountA+tokenOutputAmount; // Adjust this based on your swap logic

        // Expect the VaultSettled event to be emitted with the correct total winning token balance
        vm.expectEmit(true, true, true, true);
        emit IVault.VaultSettled(epochId, address(tokenA), expectedWinningTokenBalance);

        vm.prank(epochController);
        vault.settleVault(swapData, address(tokenA), epochId);

        // assert player1 tokenA balance is 213 after rounding off and player2 tokenA balance is 214
        uint256 player1Balance = tokenA.balanceOf(player1);
        uint256 player3Balance = tokenA.balanceOf(player3);
        assertEq(player1Balance, 213);
        assertEq(player3Balance, 214);
    }

    function testSettleVault_EpochNotFinished() public {
        uint256 depositAmountA = 100;
        uint256 depositAmountB = 200;
        uint256 gameId = 1;
        uint256 epochId = 1;
        bytes memory swapData = abi.encode(uint24(3000), address(0));

        setupAndStartEpoch(100);
        setupGame(gameId, address(tokenA), address(tokenB), depositAmountA, depositAmountB, player1, player2, player1, player2, epochId);
        depositFromGame(depositAmountA, gameId, epochId, tokenA);

        // Attempt to settle the vault before finishing the epoch
        vm.prank(epochController);
        vm.expectRevert("Epoch is not finished yet");
        vault.settleVault(swapData, address(tokenA), epochId);
    }

    function testSettleVault_NoDexAdapter() public {
        uint256 depositAmountA = 100;
        uint256 depositAmountB = 200;
        uint256 gameId = 1;
        uint256 epochId = 1;
        bytes memory swapData = abi.encode(uint24(3000), address(0));

        // Set up initial conditions without setting a DEX adapter
        address[] memory tokenAddresses = new address[](2);
        tokenAddresses[0] = address(tokenA);
        tokenAddresses[1] = address(tokenB);

        vm.prank(owner);
        vault.addSupportedToken(address(tokenA));
        vm.prank(owner);
        vault.addSupportedToken(address(tokenB));

        vm.prank(epochController);
        vault.startEpoch(tokenAddresses);

        setupGame(gameId, address(tokenA), address(tokenB), depositAmountA, depositAmountB, player1, player2, player1, player2, epochId);
        depositFromGame(depositAmountA, gameId, epochId, tokenA);
        depositFromGame(depositAmountB, gameId, epochId, tokenB);
        finishEpoch(epochId);

        // Attempt to settle the vault without a DEX adapter
        vm.prank(epochController);
        vm.expectRevert("No DEX adapter found for this pair");
        vault.settleVault(swapData, address(tokenA), epochId);
    }

    function testSettleVault_TokenTransferFailed() public {
        uint256 depositAmountA = 100;
        uint256 depositAmountB = 200;
        uint256 gameId = 1;
        uint256 epochId = 1;
        bytes memory swapData = abi.encode(uint24(3000), address(0));

        setupAndStartEpoch(100);
        setupGame(gameId, address(tokenA), address(tokenB), depositAmountA, depositAmountB, player1, player2, player1, player2, epochId);
        depositFromGame(depositAmountA, gameId, epochId, tokenA);
        finishEpoch(epochId);

        // Simulate token transfer failure
        vm.mockCall(
            address(tokenA),
            abi.encodeWithSelector(IERC20.transfer.selector, player1, 100),
            abi.encode(false)
        );

        // Attempt to settle the vault, expect a revert due to token transfer failure
        vm.prank(epochController);
        vm.expectRevert("Token transfer failed");
        vault.settleVault(swapData, address(tokenA), epochId);
    }

    function testSettleVault_InvalidWinningToken() public {
        uint256 depositAmountA = 100;
        uint256 depositAmountB = 200;
        uint256 gameId = 1;
        uint256 epochId = 1;
        bytes memory swapData = abi.encode(uint24(3000), address(0));

        setupAndStartEpoch(100);
        setupGame(gameId, address(tokenA), address(tokenB), depositAmountA, depositAmountB, player1, player2, player1, player2, epochId);
        depositFromGame(depositAmountA, gameId, epochId, tokenA);
        
        finishEpoch(epochId);

        // Attempt to settle the vault with an invalid winning token
        vm.prank(epochController);
        vm.expectRevert("Winning token is not supported");
        vault.settleVault(swapData, address(0xDEAD), epochId);
    }
}