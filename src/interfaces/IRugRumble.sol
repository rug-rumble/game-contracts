// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IRugRumble {
    /// @notice Structure to represent a game
    struct Game {
        address player1;         // Address of the first player
        address player2;         // Address of the second player
        address token1;          // ERC20 token used by player 1
        address token2;          // ERC20 token used by player 2
        uint256 wagerAmount1;    // Amount wagered by player 1
        uint256 wagerAmount2;    // Amount wagered by player 2
        bool isActive;           // Status indicating if the game is active or concluded
        address winner;          // Address of the winner
        address loser;           // Address of the loser
        uint256 epochId;         // Epoch ID of the game
    }

    /// @notice Adds a supported ERC20 token for wagering
    /// @param _token The address of the token to be supported
    function addSupportedToken(address _token) external;

    /// @notice Removes a supported ERC20 token from the list
    /// @param _token The address of the token to be removed
    function removeSupportedToken(address _token) external;

    /// @notice Sets the details for a new game with the specified gameId, tokens, wager amounts, and NFT decks
    /// @param gameId The unique ID of the game
    /// @param token1 The ERC20 token used by the first player
    /// @param token2 The ERC20 token used by the second player
    /// @param wagerAmount1 The amount wagered by the first player
    /// @param wagerAmount2 The amount wagered by the second player
    function setGame(
        uint256 gameId,
        address token1,
        address token2,
        uint256 wagerAmount1,
        uint256 wagerAmount2,
        uint256 epochId
    ) external;

    /// @notice Deposits tokens for a specific game
    /// @param gameId The unique ID of the game
    function depositForGame(
        uint256 gameId, 
        address token
    ) external;

    /// @notice Ends a game, distributes the wagered tokens, and unlocks NFTs
    /// @param gameId The unique ID of the game
    /// @param winner The address of the winner
    /// @param data Additional data for the swap adapter
    function endGame(uint256 gameId, address winner, bytes calldata data) external;

    /// @notice Refunds a game when needed, and resets active state
    /// @param gameId The unique ID of the game
    function refundGame(uint256 gameId) external;

    /// @notice Gets the details of a game by its gameId
    /// @param gameId The unique ID of the game
    /// @return The Game struct containing the game's details
    function getGame(uint256 gameId) external view returns (Game memory);

    /// @notice Updates the vault address
    /// @param _newVault The new vault address
    function updateVault(address _newVault) external;

    /// @notice Updates the owner address
    /// @param _newOwner The new owner address
    function updateOwner(address _newOwner) external;

    /// @notice Sets the DEX adapter for a specific token pair
    /// @param tokenA The first token address
    /// @param tokenB The second token address
    /// @param _dexAdapter The address of the DEX adapter
    function setDexAdapter(
        address tokenA,
        address tokenB,
        address _dexAdapter
    ) external;
}
