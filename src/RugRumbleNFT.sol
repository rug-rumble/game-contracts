// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC1155} from "openzeppelin-contracts/contracts/token/ERC1155/ERC1155.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {IRugRumbleNFT} from "./interfaces/IRugRumbleNFT.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC1155Receiver} from "openzeppelin-contracts/contracts/token/ERC1155/IERC1155Receiver.sol";

/// @title RugRumbleNFT Contract
/// @notice Implements the RugRumbleNFT game NFT functionality
contract RugRumbleNFT is
    IRugRumbleNFT,
    ERC1155,
    Ownable,
    ReentrancyGuard,
    IERC1155Receiver
{
    // State variables
    address public rugRumbleContract;
    IERC20 public paymentToken;
    address public protocolAddress;

    mapping(uint256 => mapping(address => uint256[])) public lockedNFTs;
    mapping(uint256 => MintConfig) public mintConfigs;
    uint256 public mintConfigCounter;

    // Events
    event NFTLocked(
        uint256 indexed gameId,
        address indexed player,
        uint256[] cardIds
    );
    event NFTUnlocked(
        uint256 indexed gameId,
        address indexed player,
        uint256[] cardIds
    );
    event PackPurchased(address indexed buyer, uint256[] tokenIds);
    event FreeMint(address indexed to, uint256[] tokenIds);
    event MintConfigAdded(uint256 indexed configId, bool isPaid, uint256 price);

    // Modifiers
    modifier onlyRugRumbleContract() {
        require(
            msg.sender == rugRumbleContract,
            "Caller is not the RugRumble contract"
        );
        _;
    }

    /// @notice Contract constructor
    /// @param uri_ The base URI for token metadata
    /// @param initialOwner The initial owner of the contract
    /// @param _paymentToken The address of the payment token
    /// @param _protocolAddress The address of the protocol
    constructor(
        string memory uri_,
        address initialOwner,
        address _paymentToken,
        address _protocolAddress
    ) ERC1155(uri_) Ownable(initialOwner) {
        paymentToken = IERC20(_paymentToken);
        protocolAddress = _protocolAddress;
    }

    // Admin functions

    /// @inheritdoc IRugRumbleNFT
    function setRugRumbleContract(
        address _rugRumbleContract
    ) external override onlyOwner {
        require(
            _rugRumbleContract != address(0),
            "Invalid RugRumble contract address"
        );
        rugRumbleContract = _rugRumbleContract;
    }

    /// @inheritdoc IRugRumbleNFT
    function addMintConfig(
        CardConfig[] memory cardConfigs,
        bool isPaid,
        uint256 price
    ) external override onlyOwner {
        require(
            cardConfigs.length > 0,
            "Must provide at least one card config"
        );

        MintConfig storage newConfig = mintConfigs[mintConfigCounter];
        for (uint i = 0; i < cardConfigs.length; i++) {
            newConfig.cardConfigs.push(cardConfigs[i]);
        }
        newConfig.isPaid = isPaid;
        newConfig.price = price;

        emit MintConfigAdded(mintConfigCounter, isPaid, price);
        mintConfigCounter++;
    }

    // External functions

    /// @inheritdoc IRugRumbleNFT
    function lockNFTsForGame(
        uint256 gameId,
        address player,
        uint256[] calldata cardIds
    ) external override onlyRugRumbleContract nonReentrant {
        require(cardIds.length > 0, "No cards provided");
        uint256[] memory balances = balanceOfBatch(
            _wrapAddress(player, cardIds),
            cardIds
        );
        for (uint256 i = 0; i < balances.length; i++) {
            require(balances[i] > 0, "Player does not own all cards");
        }

        lockedNFTs[gameId][player] = cardIds;

        for (uint256 i = 0; i < cardIds.length; i++) {
            safeTransferFrom(player, address(this), cardIds[i], 1, "");
        }

        emit NFTLocked(gameId, player, cardIds);
    }

    /// @inheritdoc IRugRumbleNFT
    function unlockNFTsForPlayers(
        uint256 gameId,
        address player1,
        address player2
    ) external override onlyRugRumbleContract nonReentrant {
        _unlockNFTs(gameId, player1);
        _unlockNFTs(gameId, player2);
    }

    /// @inheritdoc IRugRumbleNFT
    function freeMint(
        address to,
        uint256 configId
    ) external override onlyOwner nonReentrant {
        require(to != address(0), "Invalid recipient address");
        require(configId < mintConfigCounter, "Invalid config ID");
        require(
            !mintConfigs[configId].isPaid,
            "Cannot use paid config for free mint"
        );

        uint256[] memory mintedIds = _mintPack(to, configId);
        emit FreeMint(to, mintedIds);
    }

    /// @inheritdoc IRugRumbleNFT
    function mint(
        address to,
        uint256 configId
    ) external override onlyOwner nonReentrant {
        require(configId < mintConfigCounter, "Invalid config ID");
        MintConfig storage config = mintConfigs[configId];

        if (config.isPaid) {
            require(
                paymentToken.transferFrom(to, protocolAddress, config.price),
                "Payment transfer failed"
            );
        }

        uint256[] memory mintedIds = _mintPack(to, configId);
        emit PackPurchased(to, mintedIds);
    }

    // View functions

    /// @inheritdoc IRugRumbleNFT
    function getMintConfig(
        uint256 configId
    ) external view override returns (MintConfig memory) {
        require(configId < mintConfigCounter, "Invalid config ID");
        return mintConfigs[configId];
    }

    /// @inheritdoc IRugRumbleNFT
    function isNFTLocked(
        uint256 gameId,
        address player,
        uint256 tokenId
    ) public view returns (bool) {
        uint256[] storage lockedTokens = lockedNFTs[gameId][player];
        for (uint256 i = 0; i < lockedTokens.length; i++) {
            if (lockedTokens[i] == tokenId) {
                return true;
            }
        }
        return false;
    }

    // Internal functions

    /// @notice Unlocks NFTs for a player after a game
    /// @param gameId The ID of the game
    /// @param player The address of the player
    function _unlockNFTs(uint256 gameId, address player) internal {
        if (lockedNFTs[gameId][player].length > 0) {
            uint256[] memory cardIds = lockedNFTs[gameId][player];
            delete lockedNFTs[gameId][player];

            for (uint256 i = 0; i < cardIds.length; i++) {
                _safeTransferFrom(address(this), player, cardIds[i], 1, "");
            }

            emit NFTUnlocked(gameId, player, cardIds);
        }
    }

    /// @notice Mints a pack of NFTs based on the given configuration
    /// @param to The address to mint the NFTs to
    /// @param configId The ID of the mint configuration to use
    /// @return An array of minted token IDs
    function _mintPack(
        address to,
        uint256 configId
    ) internal returns (uint256[] memory) {
        MintConfig storage config = mintConfigs[configId];
        uint256 totalCards = 0;
        for (uint i = 0; i < config.cardConfigs.length; i++) {
            totalCards += config.cardConfigs[i].count;
        }

        uint256[] memory mintedIds = new uint256[](totalCards);
        uint256 mintedCount = 0;

        for (uint i = 0; i < config.cardConfigs.length; i++) {
            uint256 tokenId = config.cardConfigs[i].nftId;
            _mint(to, tokenId, config.cardConfigs[i].count, "");
            for (uint j = 0; j < config.cardConfigs[i].count; j++) {
                mintedIds[mintedCount] = tokenId;
                mintedCount++;
            }
        }

        return mintedIds;
    }

    /// @notice Wraps an address into an array for use with balanceOfBatch
    /// @param account The address to wrap
    /// @param ids The array of token IDs
    /// @return An array of addresses, all set to the input account
    function _wrapAddress(
        address account,
        uint256[] memory ids
    ) private pure returns (address[] memory) {
        address[] memory accounts = new address[](ids.length);
        for (uint256 i = 0; i < ids.length; i++) {
            accounts[i] = account;
        }
        return accounts;
    }

    // ERC1155Receiver functions

    /// @notice Handles the receipt of a single ERC1155 token type
    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes memory
    ) public virtual override returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    /// @notice Handles the receipt of multiple ERC1155 token types
    function onERC1155BatchReceived(
        address,
        address,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) public virtual override returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }
}
