// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IRugRumble} from "../../src/interfaces/IRugRumble.sol";

/// @title MockRugRumble Contract
/// @notice A mock implementation of the RugRumble contract for testing purposes
contract MockRugRumble is IRugRumble {
    /// @notice Mapping to store games with their unique ID
    mapping(uint256 => Game) private games;

    /// @notice Mapping to track supported ERC20 tokens
    mapping(address => bool) public supportedTokens;

    /// @notice Mapping to track user deposits by token
    mapping(address => mapping(address => uint256)) public userDeposits;

    /// @notice Address of the contract owner
    address public owner;

    /// @notice Address of the vault
    address public vault;

    /// @notice Events to log important actions in the contract
    event MockGameSet(
        uint256 indexed gameId,
        address indexed player1,
        address indexed player2,
        address token1,
        address token2,
        uint256 wagerAmount1,
        uint256 wagerAmount2
    );

    event MockGameEnded(
        uint256 indexed gameId,
        address indexed winner
    );

    /// @notice Constructor to set initial owner
    constructor() {
        owner = msg.sender;
    }

    /// @notice Modifier to restrict functions to only the contract owner
    modifier onlyOwner() {
        require(msg.sender == owner, "Caller is not the owner");
        _;
    }

    /// @inheritdoc IRugRumble
    function addSupportedToken(address _token) external onlyOwner {
        supportedTokens[_token] = true;
    }

    /// @inheritdoc IRugRumble
    function removeSupportedToken(address _token) external onlyOwner {
        supportedTokens[_token] = false;
    }

    /// @inheritdoc IRugRumble
    function deposit(address token, uint256 amount) external {
        require(supportedTokens[token], "Token not supported");
        require(amount > 0, "Amount must be greater than zero");
        
        // In a real scenario, this would use transferFrom
        // Here we're just simulating the deposit
        userDeposits[msg.sender][token] += amount;
    }

    /// @inheritdoc IRugRumble
    function withdrawDeposit(address token, uint256 amount) external {
        require(userDeposits[msg.sender][token] >= amount, "Insufficient deposit");
        
        userDeposits[msg.sender][token] -= amount;
    }

    /// @inheritdoc IRugRumble
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
        require(supportedTokens[token1], "Token1 not supported");
        require(supportedTokens[token2], "Token2 not supported");
        require(games[gameId].player1 == address(0), "Game already exists");
        
        // Simulate deposit checks
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
        
        // Deduct deposits
        userDeposits[player1][token1] -= wagerAmount1;
        userDeposits[player2][token2] -= wagerAmount2;
        
        emit MockGameSet(
            gameId,
            player1,
            player2,
            token1,
            token2,
            wagerAmount1,
            wagerAmount2
        );
    }

    /// @inheritdoc IRugRumble
    function refundUser(address user, address token, uint256 amount) external onlyOwner {
        // Simulate refund by adding back to user deposits
        userDeposits[user][token] += amount;
    }

    /// @inheritdoc IRugRumble
    function endGame(
        uint256 gameId,
        address winner,
        bytes calldata /* data */
    ) external onlyOwner {
        Game storage game = games[gameId];
        require(game.isActive, "Game is not active");
        require(
            winner == game.player1 || winner == game.player2,
            "Winner must be a participant"
        );

        game.isActive = false;
        game.winner = winner;
        game.loser = (winner == game.player1) ? game.player2 : game.player1;

        // In a mock, we'll just simulate adding the wager to the winner's deposits
        address winnerToken = (winner == game.player1) ? game.token1 : game.token2;
        uint256 winnerAmount = (winner == game.player1)
            ? game.wagerAmount1
            : game.wagerAmount2;
        
        // Simulate adding winnings (in a real scenario, this would involve token swapping)
        userDeposits[winner][winnerToken] += winnerAmount * 2;

        emit MockGameEnded(gameId, winner);
    }

    /// @inheritdoc IRugRumble
    function refundGame(uint256 gameId) external onlyOwner {
        Game storage game = games[gameId];
        require(!game.isActive || game.winner == address(0), "Game already completed");

        // Refund player 1
        if (game.player1 != address(0)) {
            userDeposits[game.player1][game.token1] += game.wagerAmount1;
        }

        // Refund player 2
        if (game.player2 != address(0)) {
            userDeposits[game.player2][game.token2] += game.wagerAmount2;
        }

        game.isActive = false;
    }

    /// @inheritdoc IRugRumble
    function getGame(uint256 gameId) external view returns (Game memory) {
        return games[gameId];
    }

    /// @inheritdoc IRugRumble
    function getUserDeposit(address user, address token) external view returns (uint256) {
        return userDeposits[user][token];
    }

    /// @inheritdoc IRugRumble
    function updateVault(address _newVault) external onlyOwner {
        vault = _newVault;
    }

    /// @inheritdoc IRugRumble
    function updateOwner(address _newOwner) external onlyOwner {
        owner = _newOwner;
    }

    /// @inheritdoc IRugRumble
    function setDexAdapter(
        address /* tokenA */,
        address /* tokenB */,
        address /* _dexAdapter */
    ) external onlyOwner {
        // Mock implementation - does nothing
    }

        function setMockGame(
        uint256 gameId,
        address player1,
        address player2,
        address token1,
        address token2,
        uint256 wagerAmount1,
        uint256 wagerAmount2,
        address winner,
        address loser,
        uint256 epochId
    ) external {
        games[gameId] = Game({
            player1: player1,
            player2: player2,
            token1: token1,
            token2: token2,
            wagerAmount1: wagerAmount1,
            wagerAmount2: wagerAmount2,
            isActive: true,
            winner: winner,
            loser: loser,
            epochId: epochId
        });
    }
}