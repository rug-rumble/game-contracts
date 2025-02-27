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
        uint256,
        address recipient,
        bytes calldata
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
        token1 = new MockERC20("Token1", "TKN1");
        token2 = new MockERC20("Token2", "TKN2");
        dexAdapter = new MockDexAdapter();

        rugRumble = new RugRumble(PROTOCOL, address(this));

        rugRumble.setDexAdapter(
            address(token1),
            address(token2),
            address(dexAdapter)
        );

        address[] memory initialSupportedTokens = new address[](2);
        initialSupportedTokens[0] = address(token1);
        initialSupportedTokens[1] = address(token2);
        vault = new Vault(
            address(rugRumble),
            initialSupportedTokens,
            address(this)
        );

        vault.grantRole(EPOCH_CONTROLLER_ROLE, address(this));
        vault.grantRole(OWNER_ROLE, address(this));

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

        vault.startEpoch(initialSupportedTokens);

        token1.mint(PLAYER1, INITIAL_BALANCE);
        token2.mint(PLAYER2, INITIAL_BALANCE);
        vm.prank(PLAYER1);
        token1.approve(address(rugRumble), WAGER_AMOUNT);
        vm.prank(PLAYER2);
        token2.approve(address(rugRumble), WAGER_AMOUNT);

        rugRumble.addSupportedToken(address(token1));
        rugRumble.addSupportedToken(address(token2));

        token1.mint(address(dexAdapter), 1000 * 10 ** 18);
        token2.mint(address(dexAdapter), 1000 * 10 ** 18);
    }

    function testSetGame() public {
        rugRumble.setGame(
            1,
            address(token1),
            address(token2),
            WAGER_AMOUNT,
            WAGER_AMOUNT,
            1
        );

        RugRumble.Game memory game = rugRumble.getGame(1);
        assertEq(game.token1, address(token1));
        assertEq(game.token2, address(token2));
        assertEq(game.wagerAmount1, WAGER_AMOUNT);
        assertEq(game.wagerAmount2, WAGER_AMOUNT);
        assertEq(game.epochId, 1);
        assertFalse(game.isActive);
    }

    function testDepositForGame() public {
        rugRumble.setGame(
            1,
            address(token1),
            address(token2),
            WAGER_AMOUNT,
            WAGER_AMOUNT,
            1
        );

        vm.prank(PLAYER1);
        rugRumble.depositForGame(1, address(token1));

        RugRumble.Game memory game = rugRumble.getGame(1);
        assertEq(game.player1, PLAYER1);

        vm.prank(PLAYER2);
        rugRumble.depositForGame(1, address(token2));

        game = rugRumble.getGame(1);
        assertEq(game.player2, PLAYER2);
        assertTrue(game.isActive);
    }

    function testRefundGame() public {
        rugRumble.setGame(
            1,
            address(token1),
            address(token2),
            WAGER_AMOUNT,
            WAGER_AMOUNT,
            1
        );

        vm.prank(PLAYER1);
        rugRumble.depositForGame(1, address(token1));

        rugRumble.refundGame(1);

        RugRumble.Game memory game = rugRumble.getGame(1);
        assertEq(game.player1, address(0));
        assertApproxEqAbs(
            token1.balanceOf(PLAYER1),
            INITIAL_BALANCE,
            1e15
        );
    }

    function testEndGame() public {
        rugRumble.setGame(
            1,
            address(token1),
            address(token2),
            WAGER_AMOUNT,
            WAGER_AMOUNT,
            1
        );

        vm.prank(PLAYER1);
        rugRumble.depositForGame(1, address(token1));
        vm.prank(PLAYER2);
        rugRumble.depositForGame(1, address(token2));

        bytes memory data = abi.encode(uint24(3000), address(0));
        rugRumble.endGame(1, PLAYER1, data);

        RugRumble.Game memory game = rugRumble.getGame(1);
        assertEq(game.winner, PLAYER1);
        assertEq(game.loser, PLAYER2);
        assertFalse(game.isActive);

        uint256 winnerShare = WAGER_AMOUNT + (WAGER_AMOUNT * 69) / 100;
        assertApproxEqAbs(
            token1.balanceOf(PLAYER1),
            INITIAL_BALANCE - WAGER_AMOUNT + winnerShare,
            1e15
        );
    }
}
