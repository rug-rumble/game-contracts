// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IRugRumble} from "./interfaces/IRugRumble.sol";
import {IVault} from "./interfaces/IVault.sol";
import {IDexAdapter} from "./swap-adapters/interfaces/IDexAdapter.sol";

/// @title RugRumble Contract
/// @notice Implements the RugRumble game functionality with deposit-first approach
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

    /// @notice Mapping of token pair hashes to DEX adapters
    mapping(bytes32 => address) public dexAdapters;

    /// @notice Mapping to track user deposits by token
    mapping(address => mapping(address => uint256)) public userDeposits;

    /// @notice Events to log important actions in the contract
    event UserDeposited(
        address indexed user,
        address indexed token,
        uint256 amount
    );

    event UserWithdrawn(
        address indexed user,
        address indexed token,
        uint256 amount
    );

    event UserRefunded(
        address indexed user,
        uint256 indexed gameId,
        address token,
        uint256 amount
    );

    event GameSet(
        uint256 indexed gameId,
        uint256 indexed epochId,
        address token1,
        address token2,
        uint256 wagerAmount1,
        uint256 wagerAmount2
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

    event GameRefunded(
        uint256 indexed gameId,
        address indexed player1,
        address indexed player2
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

    /// @notice Constructor to initialize the contract with protocol, owner addresses
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

    /// @notice Allows users to deposit tokens without a specific game ID
    /// @param token The token to deposit
    /// @param amount The amount to deposit
    function deposit(address token, uint256 amount) external nonReentrant {
        require(supportedTokens[token], "Token not supported");
        require(amount > 0, "Amount must be greater than zero");
        require(
            IERC20(token).allowance(msg.sender, address(this)) >= amount,
            "Insufficient allowance for token"
        );

        IERC20(token).transferFrom(msg.sender, address(this), amount);
        userDeposits[msg.sender][token] += amount;

        emit UserDeposited(msg.sender, token, amount);
    }

    /// @notice Allows users to withdraw their deposited tokens if not in a game
    /// @param token The token to withdraw
    /// @param amount The amount to withdraw
    function withdrawDeposit(address token, uint256 amount) external nonReentrant {
        require(userDeposits[msg.sender][token] >= amount, "Insufficient deposit");
        
        userDeposits[msg.sender][token] -= amount;
        IERC20(token).transfer(msg.sender, amount);
        
        emit UserWithdrawn(msg.sender, token, amount);
    }

    /// @inheritdoc IRugRumble
    /// @notice Creates and starts a game between two users using their existing deposits
    /// @param gameId The ID for the new game
    /// @param player1 The address of the first player
    /// @param player2 The address of the second player
    /// @param token1 The first token for the game
    /// @param token2 The second token for the game
    /// @param wagerAmount1 The wager amount for the first token
    /// @param wagerAmount2 The wager amount for the second token
    /// @param epochId The epoch ID for the game
    function setGame(
        uint256 gameId,
        address player1,
        address player2,
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
        
        // Check if both players have enough deposits
        require(userDeposits[player1][token1] >= wagerAmount1, "Player1 has insufficient deposit");
        require(userDeposits[player2][token2] >= wagerAmount2, "Player2 has insufficient deposit");
        
        // Create the game
        games[gameId] = Game({
            player1: player1,
            player2: player2,
            token1: token1,
            token2: token2,
            wagerAmount1: wagerAmount1,
            wagerAmount2: wagerAmount2,
            isActive: true,
            winner: address(0),
            loser: address(0),
            epochId: epochId
        });
        
        // Deduct deposits from users
        userDeposits[player1][token1] -= wagerAmount1;
        userDeposits[player2][token2] -= wagerAmount2;
        
        emit GameSet(
            gameId,
            epochId,
            token1,
            token2,
            wagerAmount1,
            wagerAmount2
        );
        
        emit GameStarted(gameId, player1, player2, epochId);
    }

    /// @inheritdoc IRugRumble
    /// @notice Refunds deposits to a specific user
    /// @param user The address of the user to refund
    /// @param token The token address to refund
    /// @param amount The amount to refund
    function refundUser(address user, address token, uint256 amount) external onlyOwner nonReentrant {
        require(amount > 0, "Amount must be greater than zero");
        require(IERC20(token).balanceOf(address(this)) >= amount, "Insufficient contract balance");
        
        IERC20(token).transfer(user, amount);
        
        emit UserWithdrawn(user, token, amount);
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
    function refundGame(uint256 gameId) external onlyOwner nonReentrant {
        Game storage game = games[gameId];
        require(!game.isActive || game.winner == address(0), "Game already completed");
        require(game.player1 != address(0) || game.player2 != address(0), "No deposits to refund");

        // Refund player 1 if they deposited
        if (game.player1 != address(0)) {
            IERC20(game.token1).transfer(game.player1, game.wagerAmount1);
            emit UserRefunded(
                game.player1,
                gameId,
                game.token1,
                game.wagerAmount1
            );
        }

        // Refund player 2 if they deposited
        if (game.player2 != address(0)) {
            IERC20(game.token2).transfer(game.player2, game.wagerAmount2);
            emit UserRefunded(
                game.player2,
                gameId,
                game.token2,
                game.wagerAmount2
            );
        }

        emit GameRefunded(gameId, game.player1, game.player2);

        // Reset game state
        game.isActive = false;
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

    /// @notice Returns the deposit amount for a user and token
    /// @param user The user address
    /// @param token The token address
    /// @return The amount of tokens deposited
    function getUserDeposit(address user, address token) external view returns (uint256) {
        return userDeposits[user][token];
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