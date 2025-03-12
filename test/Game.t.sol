// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../src/RugRumble.sol";
import "../src/Vault.sol";
import "../src/swap-adapters/interfaces/IDexAdapter.sol";
import "./utils/MockERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract MockDexAdapter is IDexAdapter {
    function swapExactInput(
        address fromToken,
        address toToken,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient,
        bytes calldata data
    ) external override returns (uint256) {
        IERC20(fromToken).transferFrom(msg.sender, address(this), amountIn);
        MockERC20(toToken).mint(recipient, amountIn);
        return amountIn;
    }
}

contract RugRumbleGameTest is Test {
    RugRumble public rugRumble;
    MockERC20 public token1;
    MockERC20 public token2;
    MockDexAdapter public dexAdapter;
    Vault public vault;

    address public constant PROTOCOL = address(0xbeef);
    address public constant PLAYER1 = address(0x123);
    address public constant PLAYER2 = address(0x456);

    uint256 public constant INITIAL_BALANCE = 10 * 10 ** 18;
    uint256 public constant WAGER_AMOUNT = 5 * 10 ** 18;

    bytes32 public constant EPOCH_CONTROLLER_ROLE =
        keccak256("EPOCH_CONTROLLER_ROLE");
    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");

    function setUp() public {
        // Deploy mock tokens
        token1 = new MockERC20("Token1", "TKN1");
        token2 = new MockERC20("Token2", "TKN2");
        
        // Deploy DEX adapter
        dexAdapter = new MockDexAdapter();

        // Deploy RugRumble contract
        rugRumble = new RugRumble(PROTOCOL, address(this));

        // Set DEX adapter for token pair
        rugRumble.setDexAdapter(
            address(token1),
            address(token2),
            address(dexAdapter)
        );

        // Prepare initial supported tokens for vault
        address[] memory initialSupportedTokens = new address[](2);
        initialSupportedTokens[0] = address(token1);
        initialSupportedTokens[1] = address(token2);

        // Deploy vault
        vault = new Vault(
            address(rugRumble),
            initialSupportedTokens,
            address(this)
        );

        // Grant roles to test contract
        vault.grantRole(EPOCH_CONTROLLER_ROLE, address(this));
        vault.grantRole(OWNER_ROLE, address(this));

        // Update vault address in RugRumble
        rugRumble.updateVault(address(vault));

        // Set DEX adapters for vault
        vault.setDexAdapter(
            address(token1),
            address(token2),
            address(dexAdapter)
        );
        vault.setDexAdapter(
            address(token2),
            address(token1),
            address(dexAdapter)
        );

        // Start epoch
        vault.startEpoch(initialSupportedTokens);

        // Mint tokens to players
        token1.mint(PLAYER1, INITIAL_BALANCE);
        token2.mint(PLAYER2, INITIAL_BALANCE);

        // Approve RugRumble to spend tokens
        vm.prank(PLAYER1);
        token1.approve(address(rugRumble), WAGER_AMOUNT);
        vm.prank(PLAYER2);
        token2.approve(address(rugRumble), WAGER_AMOUNT);

        // Add tokens to supported tokens list
        rugRumble.addSupportedToken(address(token1));
        rugRumble.addSupportedToken(address(token2));

        // Mint tokens to DEX adapter for swapping
        token1.mint(address(dexAdapter), 1000 * 10 ** 18);
        token2.mint(address(dexAdapter), 1000 * 10 ** 18);
    }

    function testDeposit() public {
        // Deposit tokens for PLAYER1
        vm.prank(PLAYER1);
        rugRumble.deposit(address(token1), WAGER_AMOUNT);

        // Check user deposit amount
        uint256 deposit = rugRumble.getUserDeposit(PLAYER1, address(token1));
        assertEq(deposit, WAGER_AMOUNT, "Deposit amount should match");
    }

    function testSetGame() public {
        // Deposit tokens for players
        vm.prank(PLAYER1);
        rugRumble.deposit(address(token1), WAGER_AMOUNT);
        vm.prank(PLAYER2);
        rugRumble.deposit(address(token2), WAGER_AMOUNT);

        // Set game
        rugRumble.setGame(
            1,
            PLAYER1,
            PLAYER2,
            address(token1),
            address(token2),
            WAGER_AMOUNT,
            WAGER_AMOUNT,
            1
        );

        // Verify game details
        RugRumble.Game memory game = rugRumble.getGame(1);
        assertEq(game.token1, address(token1));
        assertEq(game.token2, address(token2));
        assertEq(game.wagerAmount1, WAGER_AMOUNT);
        assertEq(game.wagerAmount2, WAGER_AMOUNT);
        assertEq(game.epochId, 1);
        assertTrue(game.isActive);
    }

    function testRefundGame() public {
        // Deposit tokens for PLAYER1
        vm.prank(PLAYER1);
        rugRumble.deposit(address(token1), WAGER_AMOUNT);

                // Deposit tokens for PLAYER1
        vm.prank(PLAYER2);
        rugRumble.deposit(address(token2), WAGER_AMOUNT);

        // Set game
        rugRumble.setGame(
            1,
            PLAYER1,
            PLAYER2,
            address(token1),
            address(token2),
            WAGER_AMOUNT,
            WAGER_AMOUNT,
            1
        );

        // Refund game
        rugRumble.refundGame(1);

        // Verify game state and player balance
        RugRumble.Game memory game = rugRumble.getGame(1);
        assertApproxEqAbs(
            token1.balanceOf(PLAYER1),
            INITIAL_BALANCE,
            1e15
        );
        assertApproxEqAbs(
            token2.balanceOf(PLAYER2),
            INITIAL_BALANCE,
            1e15
        );
    }

    function testEndGame() public {
        // Deposit tokens for players
        vm.prank(PLAYER1);
        rugRumble.deposit(address(token1), WAGER_AMOUNT);
        vm.prank(PLAYER2);
        rugRumble.deposit(address(token2), WAGER_AMOUNT);

        // Set game
        rugRumble.setGame(
            1,
            PLAYER1,
            PLAYER2,
            address(token1),
            address(token2),
            WAGER_AMOUNT,
            WAGER_AMOUNT,
            1
        );

        // Prepare swap data
        bytes memory data = abi.encode(uint24(3000), address(0));

        // End game with PLAYER1 as winner
        rugRumble.endGame(1, PLAYER1, data);

        // Verify game state
        RugRumble.Game memory game = rugRumble.getGame(1);
        assertEq(game.winner, PLAYER1);
        assertEq(game.loser, PLAYER2);
        assertFalse(game.isActive);

        // Calculate expected winner share
        uint256 winnerShare = WAGER_AMOUNT + (WAGER_AMOUNT * 69) / 100;
        uint256 expectedBalance = INITIAL_BALANCE - WAGER_AMOUNT + winnerShare;

        // Verify winner's balance
        assertApproxEqAbs(
            token1.balanceOf(PLAYER1),
            expectedBalance,
            1e15
        );
    }

    function testWithdrawDeposit() public {
        // Deposit tokens for PLAYER1
        vm.prank(PLAYER1);
        rugRumble.deposit(address(token1), WAGER_AMOUNT);

        // Withdraw deposit
        vm.prank(PLAYER1);
        rugRumble.withdrawDeposit(address(token1), WAGER_AMOUNT);

        // Verify deposit and balance
        uint256 deposit = rugRumble.getUserDeposit(PLAYER1, address(token1));
        assertEq(deposit, 0, "Deposit should be zero after withdrawal");
        assertEq(
            token1.balanceOf(PLAYER1), 
            INITIAL_BALANCE, 
            "Player balance should be restored"
        );
    }
}