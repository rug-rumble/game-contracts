// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {RugRumble} from "../src/RugRumble.sol";
import {Vault} from "../src/Vault.sol";
import {IDexAdapter} from "../src/swap-adapters/interfaces/IDexAdapter.sol";

contract RugRumbleIntegrationTest is Test {
    RugRumble public rugRumble;
    MockERC20 public token1;
    MockERC20 public token2;
    MockDexAdapter public dexAdapter;
    Vault public vault;

    address public constant PROTOCOL = address(0xbeef);
    address public constant PLAYER1 = address(0x123);
    address public constant PLAYER2 = address(0x456);

    uint256 public constant INITIAL_BALANCE = 1000 * 10 ** 18;
    uint256 public constant WAGER_AMOUNT = 50 * 10 ** 18;

    function setUp() public {
        // Deploy tokens
        token1 = new MockERC20("Token1", "TKN1");
        token2 = new MockERC20("Token2", "TKN2");
        
        // Deploy DEX adapter
        dexAdapter = new MockDexAdapter();

        // Deploy RugRumble contract
        rugRumble = new RugRumble(PROTOCOL, address(this));

        // Add supported tokens
        rugRumble.addSupportedToken(address(token1));
        rugRumble.addSupportedToken(address(token2));

        // Set DEX adapter for token pair
        rugRumble.setDexAdapter(address(token1), address(token2), address(dexAdapter));

        address[] memory initialSupportedTokens = new address[](2);
        initialSupportedTokens[0] = address(token1);
        initialSupportedTokens[1] = address(token2);
        vault = new Vault(
            address(rugRumble),
            initialSupportedTokens,
            address(this)
        );

        bytes32 epochControllerRole = keccak256("EPOCH_CONTROLLER_ROLE");
        bytes32 ownerRole = keccak256("OWNER_ROLE");
        vault.grantRole(epochControllerRole, address(this));
        vault.grantRole(ownerRole, address(this));

        rugRumble.updateVault(address(vault));

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

        _setupPlayerTokens(PLAYER1, token1);
        _setupPlayerTokens(PLAYER2, token2);

        vault.startEpoch(initialSupportedTokens);

        token1.mint(address(dexAdapter), 1000 * 10 ** 18);
        token2.mint(address(dexAdapter), 1000 * 10 ** 18);
    }

    function _setupPlayerTokens(address player, MockERC20 token) internal {
        token.mint(player, INITIAL_BALANCE);
        vm.prank(player);
        token.approve(address(rugRumble), INITIAL_BALANCE);
    }

    function testDeposit() public {
        // Player1 deposits tokens
        vm.prank(PLAYER1);
        rugRumble.deposit(address(token1), WAGER_AMOUNT);

        // Verify deposit
        assertEq(
            rugRumble.getUserDeposit(PLAYER1, address(token1)),
            WAGER_AMOUNT,
            "Deposit amount incorrect"
        );
    }

    function testWithdrawDeposit() public {
        // Player1 deposits tokens
        vm.prank(PLAYER1);
        rugRumble.deposit(address(token1), WAGER_AMOUNT);

        // Player1 withdraws tokens
        vm.prank(PLAYER1);
        rugRumble.withdrawDeposit(address(token1), WAGER_AMOUNT / 2);

        // Verify remaining deposit
        assertEq(
            rugRumble.getUserDeposit(PLAYER1, address(token1)),
            WAGER_AMOUNT / 2,
            "Withdrawal amount incorrect"
        );
    }

    function testSetGame() public {
        // Players deposit tokens
        vm.prank(PLAYER1);
        rugRumble.deposit(address(token1), WAGER_AMOUNT);
        
        vm.prank(PLAYER2);
        rugRumble.deposit(address(token2), WAGER_AMOUNT);

        uint256 gameId = 1;
        uint256 epochId = 1;

        // Set the game
        rugRumble.setGame(
            gameId,
            PLAYER1,
            PLAYER2,
            address(token1),
            address(token2),
            WAGER_AMOUNT,
            WAGER_AMOUNT,
            epochId
        );

        // Verify game details
        RugRumble.Game memory game = rugRumble.getGame(gameId);
        assertTrue(game.isActive, "Game should be active");
        assertEq(game.player1, PLAYER1, "Player1 incorrect");
        assertEq(game.player2, PLAYER2, "Player2 incorrect");
        assertEq(game.wagerAmount1, WAGER_AMOUNT, "Wager amount 1 incorrect");
        assertEq(game.wagerAmount2, WAGER_AMOUNT, "Wager amount 2 incorrect");

        // Verify deposits are deducted
        assertEq(
            rugRumble.getUserDeposit(PLAYER1, address(token1)),
            0,
            "Player1 deposit not deducted"
        );
        assertEq(
            rugRumble.getUserDeposit(PLAYER2, address(token2)),
            0,
            "Player2 deposit not deducted"
        );
    }

    function testEndGame() public {
        // Players deposit tokens
        vm.prank(PLAYER1);
        rugRumble.deposit(address(token1), WAGER_AMOUNT);
        
        vm.prank(PLAYER2);
        rugRumble.deposit(address(token2), WAGER_AMOUNT);

        uint256 gameId = 1;
        uint256 epochId = 1;

        // Set the game
        rugRumble.setGame(
            gameId,
            PLAYER1,
            PLAYER2,
            address(token1),
            address(token2),
            WAGER_AMOUNT,
            WAGER_AMOUNT,
            epochId
        );

        // Prepare swap data
        bytes memory data = abi.encode(uint24(3000), address(0));

        // End game with PLAYER1 as winner
        rugRumble.endGame(gameId, PLAYER1, data);

        // Verify game state
        RugRumble.Game memory game = rugRumble.getGame(gameId);
        assertFalse(game.isActive, "Game should be inactive");
        assertEq(game.winner, PLAYER1, "Winner incorrect");
        assertEq(game.loser, PLAYER2, "Loser incorrect");
    }

    function testRefundGame() public {
        // Players deposit tokens
        vm.prank(PLAYER1);
        rugRumble.deposit(address(token1), WAGER_AMOUNT);
        
        vm.prank(PLAYER2);
        rugRumble.deposit(address(token2), WAGER_AMOUNT);

        uint256 gameId = 1;
        uint256 epochId = 1;

        // Set the game
        rugRumble.setGame(
            gameId,
            PLAYER1,
            PLAYER2,
            address(token1),
            address(token2),
            WAGER_AMOUNT,
            WAGER_AMOUNT,
            epochId
        );

        // Refund the game
        rugRumble.refundGame(gameId);

        // Verify game state
        RugRumble.Game memory game = rugRumble.getGame(gameId);
        assertFalse(game.isActive, "Game should be inactive");

        // Verify deposits are refunded
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
}

// Mock ERC20 token for testing
contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1000000 * 10 ** 18);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

// Mock DEX adapter for testing
contract MockDexAdapter is IDexAdapter {
    function swapExactInput(
        address fromToken,
        address toToken,
        uint256 amountIn,
        uint256,
        address recipient,
        bytes calldata
    ) external override returns (uint256 amountOut) {
        IERC20(fromToken).transferFrom(msg.sender, address(this), amountIn);
        MockERC20(toToken).mint(recipient, amountIn);
        return amountIn;
    }
}