// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
pragma abicoder v2;

import {AccessControlEnumerable} from "openzeppelin-contracts/contracts/access/extensions/AccessControlEnumerable.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IRugRumble} from "./interfaces/IRugRumble.sol";
import "./swap-adapters/interfaces/IDexAdapter.sol";
import {IVault} from  "./interfaces/IVault.sol";

contract Vault is IVault, ReentrancyGuard, AccessControlEnumerable {

    bytes32 public constant EPOCH_CONTROLLER_ROLE = keccak256("EPOCH_CONTROLLER_ROLE");
    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");
    bytes32 public constant GAME_CONTRACT_ROLE = keccak256("GAME_CONTRACT_ROLE");

    uint256 public lastEpochId;
    IRugRumble public gameContract;

    mapping(address => bool) public supportedTokens;
    mapping(bytes32 => address) public dexAdapters;
    mapping(uint256 => Epoch) public epochs;
    mapping(uint256 => uint256[]) public epochGames;
    mapping(uint256 => mapping(address => uint256)) public epochDeposits;
    mapping(address => uint256) public failedTokenSwaps;

    constructor(address _gameContract, address[] memory _supportedTokens, address _defaultAdmin) {
        require(_gameContract != address(0), "Game contract cannot be zero address");
        require(_defaultAdmin != address(0), "Default admin cannot be zero address");

        gameContract = IRugRumble(_gameContract);

        for (uint256 i = 0; i < _supportedTokens.length; i++) {
            supportedTokens[_supportedTokens[i]] = true;
        }
        _grantRole(DEFAULT_ADMIN_ROLE, _defaultAdmin);
        _grantRole(GAME_CONTRACT_ROLE, _gameContract);
        _grantRole(OWNER_ROLE, _defaultAdmin);
        _grantRole(EPOCH_CONTROLLER_ROLE, _defaultAdmin);
    }

    function getEpoch(uint256 epochId) external view returns (Epoch memory) {
        return epochs[epochId];
    }

    function getEpochGames(uint256 epochId) external view returns (uint256[] memory) {
        return epochGames[epochId];
    }

    function addSupportedToken(address tokenAddress) external onlyRole(OWNER_ROLE) {
        require(!supportedTokens[tokenAddress], "Token already supported");
        supportedTokens[tokenAddress] = true;
        emit TokenAdded(tokenAddress, msg.sender);
    }

    function updateGameContract(address _gameContract) external onlyRole(OWNER_ROLE) {
        require(_gameContract != address(0), "Game contract cannot be zero address");
        gameContract = IRugRumble(_gameContract);
    }

    function setDexAdapter(
        address tokenA,
        address tokenB,
        address _dexAdapter
    ) external onlyRole(OWNER_ROLE) {
        require(tokenA != address(0) && tokenB != address(0), "Invalid token address");
        require(_dexAdapter != address(0), "Invalid DEX adapter address");

        bytes32 pairHash = keccak256(abi.encodePacked(tokenA, tokenB));
        dexAdapters[pairHash] = _dexAdapter;

        bytes32 reversePairHash = keccak256(abi.encodePacked(tokenB, tokenA));
        dexAdapters[reversePairHash] = _dexAdapter;
    }


    function startEpoch(address[] memory tokenAddresses) external onlyRole(EPOCH_CONTROLLER_ROLE) {
        lastEpochId++;
        Epoch storage newEpoch = epochs[lastEpochId];
        newEpoch.epochId = lastEpochId;
        newEpoch.state = EpochState.STARTED;

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            require(supportedTokens[tokenAddresses[i]], "Token is not supported by vault");
            newEpoch.supportedTokens.push(tokenAddresses[i]);
        }

        emit EpochStarted(lastEpochId, tokenAddresses);
    }

    function endEpoch(uint256 epochId) external onlyRole(EPOCH_CONTROLLER_ROLE) {
        Epoch storage epoch = epochs[epochId];
        require(epoch.state == EpochState.STARTED, "Epoch is not started");
        epoch.state = EpochState.FINISHED;

        emit EpochFinished(epochId);
    }

    function depositFromGame(uint256 epochId, uint256 gameId, address token, uint256 amount) external nonReentrant onlyRole(GAME_CONTRACT_ROLE) {
        Epoch storage epoch = epochs[epochId];
        require(epoch.state == EpochState.STARTED, "Epoch is not started");
        require(supportedTokens[token], "Token not supported");

        // Assuming the game contract has already approved the tokens to this contract, pull the tokens
        require(IERC20(token).transferFrom(msg.sender, address(this), amount), "Token transfer failed");

        epochDeposits[epochId][token] += amount;
        epochGames[epochId].push(gameId);

        emit DepositFromGame(epochId, gameId, token, amount);
    }

    function settleVault(bytes calldata swapData, address winningTokenAddress, uint256 epochId) external nonReentrant onlyRole(EPOCH_CONTROLLER_ROLE) {
        Epoch storage epoch = epochs[epochId];
        require(epoch.state == EpochState.FINISHED, "Epoch is not finished yet");
        require(supportedTokens[winningTokenAddress], "Winning token is not supported");
        
        // Use dynamic arrays to track player data in memory
        uint256[] memory epochGamesArray = epochGames[epochId];
        address[] memory eligiblePlayers = new address[](epochGamesArray.length);
        uint256[] memory playerWagerAmounts = new uint256[](epochGamesArray.length);
        uint256 playerCount = 0;

        // Swap all non-winning tokens to winningTokenAddress
        uint256 winningTokenBalance = _swapNonWinningTokens(epochId, winningTokenAddress, swapData);

        // Calculate total wagers and track eligible players
        uint256 totalWagerAmount = 0;
        for (uint256 i = 0; i < epochGamesArray.length; i++) {
            uint256 gameId = epochGamesArray[i];
            IRugRumble.Game memory game = gameContract.getGame(gameId);

            if (game.token1 == winningTokenAddress) {
                (playerCount, totalWagerAmount) = _updatePlayerWager(
                    eligiblePlayers, 
                    playerWagerAmounts, 
                    playerCount, 
                    totalWagerAmount, 
                    game.player1, 
                    game.wagerAmount1
                );
            } else if (game.token2 == winningTokenAddress) {
                (playerCount, totalWagerAmount) = _updatePlayerWager(
                    eligiblePlayers, 
                    playerWagerAmounts, 
                    playerCount, 
                    totalWagerAmount, 
                    game.player2, 
                    game.wagerAmount2
                );
            }
        }

        // Resize eligiblePlayers and playerWagerAmounts arrays to actual size
        assembly { 
            mstore(eligiblePlayers, playerCount)
            mstore(playerWagerAmounts, playerCount)
        }

        // Distribute the winning tokens to eligible players
        _distributeWinnings(epochId, winningTokenAddress, eligiblePlayers, playerWagerAmounts, winningTokenBalance, totalWagerAmount);

        // Emit the VaultSettled event after distribution is complete
        epoch.state = EpochState.SETTLED;
        emit VaultSettled(epochId, winningTokenAddress, winningTokenBalance);
    }

    function _swapNonWinningTokens(uint256 epochId, address winningTokenAddress, bytes calldata swapData) internal returns (uint256 winningTokenBalance) {
        Epoch storage epoch = epochs[epochId];
        mapping(address => uint256) storage deposits = epochDeposits[epochId];

        for (uint256 i = 0; i < epoch.supportedTokens.length; i++) {
            address token = epoch.supportedTokens[i];
            uint256 tokenBalance = deposits[token];

            if (token != winningTokenAddress && tokenBalance > 0) {
                (uint256 tokensReceived, bool success) = _swapToken(token, winningTokenAddress, tokenBalance, swapData);
                if (success) {
                    winningTokenBalance += tokensReceived;
                    emit TokenSwapped(epochId, token, winningTokenAddress, tokenBalance, tokensReceived);
                } else {
                    failedTokenSwaps[token] += tokenBalance;
                    emit SwapFailed(epochId, token, tokenBalance);
                }
            } else if (token == winningTokenAddress) {
                winningTokenBalance += tokenBalance;
            }
        }
    }

    function _swapToken(address fromToken, address toToken, uint256 amount, bytes calldata swapData) internal returns (uint256 tokensReceived, bool success) {
        bytes32 pairHash = keccak256(abi.encodePacked(fromToken, toToken));
        address dexAdapter = dexAdapters[pairHash];
        require(dexAdapter != address(0), "No DEX adapter found for this pair");

        require(IERC20(fromToken).approve(dexAdapter, amount), "Token transfer failed");

        try IDexAdapter(dexAdapter).swapExactInput(fromToken, toToken, amount, 0, address(this), swapData) returns (uint256 amountOut) {
            tokensReceived = amountOut;
            success = true;
        } catch {
            success = false;
        }
    }

    function _distributeWinnings(uint256 epochId, address winningTokenAddress, address[] memory eligiblePlayers, uint256[] memory playerWagerAmounts, uint256 winningTokenBalance, uint256 totalWagerAmount) internal {
        uint256 totalDistributed = 0;
        uint256 lastIndex = eligiblePlayers.length - 1;

        for (uint256 i = 0; i < lastIndex; i++) {
            uint256 amountToGive = (playerWagerAmounts[i] * winningTokenBalance) / totalWagerAmount;
            totalDistributed += amountToGive;
            require(IERC20(winningTokenAddress).transfer(eligiblePlayers[i], amountToGive), "Token transfer failed");
            emit TokenTransfered(epochId, winningTokenAddress, eligiblePlayers[i], amountToGive);
        }

        // Distribute remaining balance to the last player
        uint256 remainingAmount = winningTokenBalance - totalDistributed;
        require(IERC20(winningTokenAddress).transfer(eligiblePlayers[lastIndex], remainingAmount), "Token transfer failed");
        emit TokenTransfered(epochId, winningTokenAddress, eligiblePlayers[lastIndex], remainingAmount);
    }
    // Helper function to update player wager and track eligible players
    function _updatePlayerWager(
        address[] memory eligiblePlayers, 
        uint256[] memory playerWagerAmounts, 
        uint256 playerCount, 
        uint256 totalWagerAmount, 
        address player, 
        uint256 wagerAmount
    ) internal pure returns (uint256, uint256) {
        for (uint256 j = 0; j < playerCount; j++) {
            if (eligiblePlayers[j] == player) {
                playerWagerAmounts[j] += wagerAmount;
                return (playerCount, totalWagerAmount + wagerAmount);
            }
        }
        eligiblePlayers[playerCount] = player;
        playerWagerAmounts[playerCount] = wagerAmount;
        return (playerCount + 1, totalWagerAmount + wagerAmount);
    }

    function transferOwnership(address newOwner) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newOwner != address(0), "New owner cannot be zero address");
        
        // Revoke roles from old admin
        address oldAdmin = getRoleMember(DEFAULT_ADMIN_ROLE, 0);
        _revokeRole(DEFAULT_ADMIN_ROLE, oldAdmin);
        _revokeRole(OWNER_ROLE, oldAdmin);
        _revokeRole(EPOCH_CONTROLLER_ROLE, oldAdmin);
        
        // Grant roles to new admin
        _grantRole(DEFAULT_ADMIN_ROLE, newOwner);
        _grantRole(OWNER_ROLE, newOwner);
        _grantRole(EPOCH_CONTROLLER_ROLE, newOwner);
    }
}
