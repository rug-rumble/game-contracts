// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
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
        token1 = new MockERC20("Token1", "TKN1");
        token2 = new MockERC20("Token2", "TKN2");
        dexAdapter = new MockDexAdapter();

        rugRumble = new RugRumble(PROTOCOL, address(this));
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

        rugRumble.addSupportedToken(address(token1));
        rugRumble.addSupportedToken(address(token2));
    }

    function _setupPlayerTokens(address player, MockERC20 token) internal {
        token.mint(player, INITIAL_BALANCE);
        vm.prank(player);
        token.approve(address(rugRumble), WAGER_AMOUNT);
    }

    function testFullGameFlow() public {
        uint256 gameId = 1;
        rugRumble.setGame(
            gameId,
            address(token1),
            address(token2),
            WAGER_AMOUNT,
            WAGER_AMOUNT,
            1
        );

        vm.prank(PLAYER1);
        rugRumble.depositForGame(gameId);

        vm.prank(PLAYER2);
        rugRumble.depositForGame(gameId);

        RugRumble.Game memory game = rugRumble.getGame(gameId);
        assertTrue(game.isActive, "Game should be active");
        assertEq(game.player1, PLAYER1, "Player1 should be set correctly");
        assertEq(game.player2, PLAYER2, "Player2 should be set correctly");

        bytes memory data = abi.encode(uint24(3000), address(0));
        rugRumble.endGame(gameId, PLAYER1, data);

        game = rugRumble.getGame(gameId);
        assertFalse(game.isActive, "Game should not be active");
        assertEq(game.winner, PLAYER1, "Winner should be PLAYER1");
        assertEq(game.loser, PLAYER2, "Loser should be PLAYER2");

        uint256 winnerShareExtra = (WAGER_AMOUNT * 69) / 100;
        uint256 winnerShare = WAGER_AMOUNT + winnerShareExtra;
        uint256 protocolShare = (WAGER_AMOUNT * 1) / 100;
        uint256 vaultShare = WAGER_AMOUNT - winnerShareExtra - protocolShare;

        assertApproxEqAbs(
            token1.balanceOf(PLAYER1),
            INITIAL_BALANCE - WAGER_AMOUNT + winnerShare,
            1e15,
            "Winner's balance is incorrect"
        );
        assertEq(
            token1.balanceOf(PROTOCOL),
            protocolShare,
            "Protocol share is incorrect"
        );
        assertEq(
            token1.balanceOf(address(vault)),
            vaultShare,
            "Vault share is incorrect"
        );
    }
}

// Mock contracts remain the same
contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1000000 * 10 ** 18);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

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
