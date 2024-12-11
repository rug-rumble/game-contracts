// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {IRugRumble} from "./interfaces/IRugRumble.sol";
import {IVault} from "./interfaces/IVault.sol";
import {IDexAdapter} from "./swap-adapters/interfaces/IDexAdapter.sol";

/// @title RugRumble Contract
/// @notice Implements the RugRumble game functionality
contract RugRumble is IRugRumble, ReentrancyGuard {
    /// @notice Address where a portion of the wagered tokens will be sent
    address public vault;

    /// @notice Address of the contract owner with administrative privileges
    address public owner;

    /// @notice Address of the protocol to receive a percentage of the wager
    address public protocol;

    /// @notice Mapping to store games with their unique ID
    mapping(uint256 => Game) public games;

    /// @notice Mapping to track supported ERC20 tokens
    mapping(address => bool) public supportedTokens;

    mapping(bytes32 => address) public dexAdapters;

    /// @notice Events to log important actions in the contract
    event GameSet(
        uint256 indexed gameId,
        uint256 indexed epochId,
        address token1,
        address token2,
        uint256 wagerAmount1,
        uint256 wagerAmount2
    );

    event TokenDeposited(
        uint256 indexed gameId,
        address indexed player,
        address indexed token,
        uint256 epochId,
        uint256 amount
    );

    event GameStarted(
        uint256 indexed gameId,
        address indexed player1,
        address indexed player2,
        uint256 epochId
    );

    event GameEnded(
        uint256 indexed gameId,
        address indexed winner,
        address indexed loser,
        uint256 epochId,
        uint256 rewardAmount,
        address winnerToken,
        address loserToken
    );

    event WagerDistributed(
        uint256 indexed gameId,
        address indexed winner,
        uint256 winnerShare,
        uint256 vaultShare,
        uint256 protocolShare,
        address winnerToken,
        address loserToken
    );

    /// @notice Modifier to restrict functions to only the contract owner
    modifier onlyOwner() {
        require(msg.sender == owner, "Caller is not the owner");
        _;
    }

    /// @notice Constructor to initialize the contract with vault, protocol, owner addresses
    /// @param _protocol The address of the protocol to receive a percentage of the wager
    /// @param _owner The address of the contract owner
    constructor(address _protocol, address _owner) {
        require(_protocol != address(0), "Invalid protocol address");
        protocol = _protocol;
        owner = _owner;
    }

    /// @inheritdoc IRugRumble
    function addSupportedToken(address token) external onlyOwner {
        require(token != address(0), "Invalid token address");
        supportedTokens[token] = true;
    }

    /// @inheritdoc IRugRumble
    function removeSupportedToken(address token) external onlyOwner {
        require(token != address(0), "Invalid token address");
        supportedTokens[token] = false;
    }

    function setDexAdapter(
        address tokenA,
        address tokenB,
        address _dexAdapter
    ) external onlyOwner {
        require(
            tokenA != address(0) && tokenB != address(0),
            "Invalid token address"
        );
        require(_dexAdapter != address(0), "Invalid DEX adapter address");

        bytes32 pairHash = keccak256(abi.encodePacked(tokenA, tokenB));
        dexAdapters[pairHash] = _dexAdapter;

        bytes32 reversePairHash = keccak256(abi.encodePacked(tokenB, tokenA));
        dexAdapters[reversePairHash] = _dexAdapter;
    }

    /// @inheritdoc IRugRumble
    function setGame(
        uint256 gameId,
        address token1,
        address token2,
        uint256 wagerAmount1,
        uint256 wagerAmount2,
        uint256 epochId
    ) external onlyOwner {
        require(vault != address(0), "Invalid vault address");
        require(supportedTokens[token1], "Token1 not supported");
        require(supportedTokens[token2], "Token2 not supported");
        require(
            wagerAmount1 > 0 && wagerAmount2 > 0,
            "Wager amounts must be greater than zero"
        );
        require(games[gameId].player1 == address(0), "Game already exists");

        games[gameId] = Game({
            player1: address(0),
            player2: address(0),
            token1: token1,
            token2: token2,
            wagerAmount1: wagerAmount1,
            wagerAmount2: wagerAmount2,
            isActive: false,
            winner: address(0),
            loser: address(0),
            epochId: epochId
        });

        emit GameSet(
            gameId,
            epochId,
            token1,
            token2,
            wagerAmount1,
            wagerAmount2
        );
    }

    /// @inheritdoc IRugRumble
    function depositForGame(uint256 gameId) external nonReentrant {
        Game storage game = games[gameId];
        require(!game.isActive, "Game is already active");

        if (game.player1 == address(0)) {
            require(
                IERC20(game.token1).allowance(msg.sender, address(this)) >=
                    game.wagerAmount1,
                "Insufficient allowance for token1"
            );
            IERC20(game.token1).transferFrom(
                msg.sender,
                address(this),
                game.wagerAmount1
            );
            game.player1 = msg.sender;
        } else {
            require(
                IERC20(game.token2).allowance(msg.sender, address(this)) >=
                    game.wagerAmount2,
                "Insufficient allowance for token2"
            );
            IERC20(game.token2).transferFrom(
                msg.sender,
                address(this),
                game.wagerAmount2
            );
            game.player2 = msg.sender;

            // Start the game when the second player deposits
            startGame(gameId);
        }

        emit TokenDeposited(
            gameId,
            msg.sender,
            game.player1 == msg.sender ? game.token1 : game.token2,
            game.epochId,
            game.player1 == msg.sender ? game.wagerAmount1 : game.wagerAmount2
        );
    }

    /// @notice Internal function to start a game once both players have deposited their tokens
    /// @param gameId The unique ID of the game
    function startGame(uint256 gameId) internal {
        Game storage game = games[gameId];
        require(
            game.player1 != address(0) && game.player2 != address(0),
            "Both players must be present"
        );

        game.isActive = true;
        emit GameStarted(gameId, game.player1, game.player2, game.epochId);
    }

    struct GameVars {
        address winnerToken;
        address loserToken;
        uint256 winnerAmount;
        uint256 loserAmount;
        uint256 swappedAmount;
        uint256 winnerShare;
        uint256 vaultShare;
        uint256 protocolShare;
    }

    /// @inheritdoc IRugRumble
    function endGame(
        uint256 gameId,
        address winner,
        bytes calldata data
    ) external onlyOwner nonReentrant {
        Game storage game = games[gameId];
        require(game.isActive, "Game is not active");
        require(
            winner == game.player1 || winner == game.player2,
            "Winner must be a participant"
        );

        game.isActive = false;
        game.winner = winner;
        game.loser = (winner == game.player1) ? game.player2 : game.player1;

        GameVars memory vars;
        vars.winnerToken = (winner == game.player1) ? game.token1 : game.token2;
        vars.loserToken = (winner == game.player1) ? game.token2 : game.token1;
        vars.winnerAmount = (winner == game.player1)
            ? game.wagerAmount1
            : game.wagerAmount2;
        vars.loserAmount = (winner == game.player1)
            ? game.wagerAmount2
            : game.wagerAmount1;

        // Swap tokens
        bytes32 pairHash = keccak256(
            abi.encodePacked(vars.loserToken, vars.winnerToken)
        );
        address dexAdapter = dexAdapters[pairHash];
        IERC20(vars.loserToken).approve(address(dexAdapter), vars.loserAmount);

        vars.swappedAmount = IDexAdapter(dexAdapter).swapExactInput(
            vars.loserToken,
            vars.winnerToken,
            vars.loserAmount,
            0,
            address(this),
            data
        );

        // Calculate shares
        uint256 winnerShareExtra = (vars.swappedAmount * 69) / 100;
        vars.winnerShare = vars.winnerAmount + winnerShareExtra;
        vars.protocolShare = (vars.swappedAmount * 1) / 100;
        vars.vaultShare =
            vars.swappedAmount -
            winnerShareExtra -
            vars.protocolShare;

        // Transfer shares
        IERC20(vars.winnerToken).transfer(winner, vars.winnerShare);
        IERC20(vars.winnerToken).transfer(protocol, vars.protocolShare);

        // Give approval to vault and call depositFromGame
        IERC20(vars.winnerToken).approve(vault, vars.vaultShare);
        IVault(vault).depositFromGame(
            game.epochId,
            gameId,
            vars.winnerToken,
            vars.vaultShare
        );

        emit GameEnded(
            gameId,
            winner,
            game.loser,
            game.epochId,
            vars.winnerShare,
            vars.winnerToken,
            vars.loserToken
        );
        emit WagerDistributed(
            gameId,
            winner,
            vars.winnerShare,
            vars.vaultShare,
            vars.protocolShare,
            vars.winnerToken,
            vars.loserToken
        );
    }

    /// @inheritdoc IRugRumble
    function getGame(uint256 gameId) external view returns (Game memory) {
        return games[gameId];
    }

    /// @inheritdoc IRugRumble
    function updateVault(address newVault) external onlyOwner {
        require(newVault != address(0), "Invalid vault address");
        vault = newVault;
    }

    /// @inheritdoc IRugRumble
    function updateOwner(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Invalid owner address");
        owner = newOwner;
    }
}
