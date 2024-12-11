// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC1155} from "openzeppelin-contracts/contracts/token/ERC1155/IERC1155.sol";

/// @title Interface for the RugRumbleNFT contract
/// @notice Defines the structure and functions for the RugRumbleNFT game NFTs
interface IRugRumbleNFT is IERC1155 {
    /// @notice Represents the rarity levels of the NFTs
    enum Rarity {
        COMMON,
        RARE,
        EPIC,
        LEGENDARY
    }

    /// @notice Configuration for a card type in a mint pack
    struct CardConfig {
        Rarity rarity;
        uint256 count;
        uint256 nftId;
    }

    /// @notice Configuration for a mint operation
    struct MintConfig {
        CardConfig[] cardConfigs;
        bool isPaid;
        uint256 price;
    }

    /// @notice Locks NFTs for a game
    /// @param gameId The ID of the game
    /// @param player The address of the player
    /// @param cardIds The IDs of the cards to lock
    function lockNFTsForGame(
        uint256 gameId,
        address player,
        uint256[] calldata cardIds
    ) external;

    /// @notice Unlocks NFTs for players after a game
    /// @param gameId The ID of the game
    /// @param player1 The address of the first player
    /// @param player2 The address of the second player
    function unlockNFTsForPlayers(
        uint256 gameId,
        address player1,
        address player2
    ) external;

    /// @notice Sets the RugRumble contract address
    /// @param rugRumbleContract The address of the RugRumble contract
    function setRugRumbleContract(address rugRumbleContract) external;

    /// @notice Adds a new mint configuration
    /// @param cardConfigs The configurations for the cards in the mint pack
    /// @param isPaid Whether the mint is paid or free
    /// @param price The price of the mint if it's paid
    function addMintConfig(
        CardConfig[] memory cardConfigs,
        bool isPaid,
        uint256 price
    ) external;

    /// @notice Performs a free mint for a given address
    /// @param to The address to mint the NFTs to
    /// @param configId The ID of the mint configuration to use
    function freeMint(address to, uint256 configId) external;

    /// @notice Performs a paid mint for a given address
    /// @param to The address to mint the NFTs to
    /// @param configId The ID of the mint configuration to use
    function mint(address to, uint256 configId) external;

    /// @notice Retrieves a mint configuration
    /// @param configId The ID of the mint configuration
    /// @return The mint configuration
    function getMintConfig(uint256 configId) external view returns (MintConfig memory);

    /// @notice Checks if a specific NFT is locked for a game
    /// @param gameId The ID of the game
    /// @param player The address of the player
    /// @param tokenId The ID of the token to check
    /// @return Whether the NFT is locked or not
    function isNFTLocked(
        uint256 gameId,
        address player,
        uint256 tokenId
    ) external view returns (bool);
}
