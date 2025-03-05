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

    uint256 public constant BATCH_SIZE = 100;

    mapping(address => bool) public supportedTokens;
    mapping(bytes32 => address) public dexAdapters;
    mapping(uint256 => Epoch) public epochs;
    mapping(uint256 => uint256[]) public epochGames;
    mapping(uint256 => mapping(address => uint256)) public epochDeposits;
    mapping(address => uint256) public failedTokenSwaps;
    mapping(uint256 => SettlementInfo) public settlementInfo;
    mapping(uint256 => mapping(address => uint256)) public playerWagers;
    mapping(uint256 => address[]) public epochEligiblePlayers;

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

    function getEligiblePlayers(uint256 epochId) external view returns (address[] memory) {
        return epochEligiblePlayers[epochId];
    }

    function getPlayerWager(uint256 epochId, address player) external view returns (uint256) {
        return playerWagers[epochId][player];
    }

    function getSettlementInfo(uint256 epochId) external view returns (SettlementInfo memory) {
        return settlementInfo[epochId];
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

    // Step 1: Initialize settlement process
    function initSettlement(uint256 epochId, address winningTokenAddress) external onlyRole(EPOCH_CONTROLLER_ROLE) {
        Epoch storage epoch = epochs[epochId];
        require(epoch.state == EpochState.FINISHED, "Epoch is not finished yet");
        require(supportedTokens[winningTokenAddress], "Winning token is not supported");
        
        // Initialize settlement info
        SettlementInfo storage settlement = settlementInfo[epochId];
        require(settlement.processedGameCount == 0, "Settlement already initialized");
        
        epoch.winningToken = winningTokenAddress;
        emit SettlementInitialized(epochId, winningTokenAddress);
    }

    // Step 2: Process games in batches
    function processGamesBatch(uint256 epochId, uint256 batchSize) external nonReentrant onlyRole(EPOCH_CONTROLLER_ROLE) {
        Epoch storage epoch = epochs[epochId];
        require(epoch.state == EpochState.FINISHED, "Epoch is not finished yet");
        require(epoch.winningToken != address(0), "Winning token not set");
        
        SettlementInfo storage settlement = settlementInfo[epochId];
        uint256[] memory epochGamesArray = epochGames[epochId];
        
        uint256 endIdx = settlement.processedGameCount + batchSize;
        if (endIdx > epochGamesArray.length) {
            endIdx = epochGamesArray.length;
        } 
        
        for (uint256 i = settlement.processedGameCount; i < endIdx; i++) {
            uint256 gameId = epochGamesArray[i];
            IRugRumble.Game memory game = gameContract.getGame(gameId);
            
            if (game.token1 == epoch.winningToken) {
                _updatePlayerWager(epochId, game.player1, game.wagerAmount1);
                settlement.totalWagerAmount += game.wagerAmount1;
            } else if (game.token2 == epoch.winningToken) {
                _updatePlayerWager(epochId, game.player2, game.wagerAmount2);
                settlement.totalWagerAmount += game.wagerAmount2;
            }
        }
        
        settlement.processedGameCount = endIdx;
        
        emit GamesBatchProcessed(epochId, settlement.processedGameCount, epochGamesArray.length);
        
        // If all games are processed
        if (settlement.processedGameCount == epochGamesArray.length) {
            emit AllGamesProcessed(epochId, settlement.playerCount, settlement.totalWagerAmount);
        }
    }

    // Step 3: Swap tokens
    function swapTokens(uint256 epochId, bytes calldata swapData) external nonReentrant onlyRole(EPOCH_CONTROLLER_ROLE) {
        Epoch storage epoch = epochs[epochId];
        SettlementInfo storage settlement = settlementInfo[epochId];
        
        require(epoch.state == EpochState.FINISHED, "Epoch is not finished yet");
        require(epoch.winningToken != address(0), "Winning token not set");
        require(settlement.processedGameCount == epochGames[epochId].length, "Not all games processed");
        require(!settlement.isSwapCompleted, "Swap already completed");
        
        uint256 winningTokenBalance = _swapNonWinningTokens(epochId, epoch.winningToken, swapData);
        settlement.winningTokenBalance = winningTokenBalance;
        settlement.isSwapCompleted = true;
        
        emit TokensSwapped(epochId, epoch.winningToken, winningTokenBalance);
    }

    // Step 4: Distribute winnings in batches
    function distributeWinningsBatch(uint256 epochId, uint256 batchSize) external nonReentrant onlyRole(EPOCH_CONTROLLER_ROLE) {
        Epoch storage epoch = epochs[epochId];
        SettlementInfo storage settlement = settlementInfo[epochId];
        
        require(epoch.state == EpochState.FINISHED, "Epoch is not finished yet");
        require(settlement.isSwapCompleted, "Tokens not swapped yet");
        require(!settlement.isFullyDistributed, "Distribution already completed");
        
        address[] memory players = epochEligiblePlayers[epochId];
        uint256 totalDistributedSoFar = 0;
        uint256 startIdx = 0;
        uint256 endIdx = players.length;
        
        // Find start index (continue from where we left off)
        for (uint256 i = 0; i < players.length; i++) {
            address player = players[i];
            if (playerWagers[epochId][player] > 0) {
                startIdx = i;
                break;
            }
        }
        
        // Adjust end index based on batch size
        if (startIdx + batchSize < players.length) {
            endIdx = startIdx + batchSize;
        }
        
        // Calculate total distributed so far
        for (uint256 i = 0; i < startIdx; i++) {
            address player = players[i];
            uint256 wagerAmount = playerWagers[epochId][player];
            if (wagerAmount > 0) {
                uint256 distributedAmount = (wagerAmount * settlement.winningTokenBalance) / settlement.totalWagerAmount;
                totalDistributedSoFar += distributedAmount;
                // Mark as distributed by setting wager to 0
                playerWagers[epochId][player] = 0;
            }
        }
        
        // Process this batch
        for (uint256 i = startIdx; i < endIdx - 1; i++) {
            address player = players[i];
            uint256 wagerAmount = playerWagers[epochId][player];
            if (wagerAmount > 0) {
                uint256 amountToGive = (wagerAmount * settlement.winningTokenBalance) / settlement.totalWagerAmount;
                totalDistributedSoFar += amountToGive;
                require(IERC20(epoch.winningToken).transfer(player, amountToGive), "Token transfer failed");
                emit TokenTransfered(epochId, epoch.winningToken, player, amountToGive);
                // Mark as distributed
                playerWagers[epochId][player] = 0;
            }
        }
        
        // If this is the last batch, handle the last player separately to account for rounding errors
        if (endIdx == players.length) {
            address lastPlayer = players[players.length - 1];
            uint256 lastPlayerWager = playerWagers[epochId][lastPlayer];
            if (lastPlayerWager > 0) {
                uint256 remainingAmount = settlement.winningTokenBalance - totalDistributedSoFar;
                require(IERC20(epoch.winningToken).transfer(lastPlayer, remainingAmount), "Token transfer failed");
                emit TokenTransfered(epochId, epoch.winningToken, lastPlayer, remainingAmount);
                // Mark as distributed
                playerWagers[epochId][lastPlayer] = 0;
                settlement.isFullyDistributed = true;
                epoch.state = EpochState.SETTLED;
                emit VaultSettled(epochId, epoch.winningToken, settlement.winningTokenBalance);
            }
        }
        
        emit DistributionBatchProcessed(epochId, endIdx, players.length);
    }

    // FAILSAFE FUNCTIONS

    // Allow admin to rescue tokens stuck in the contract
    function emergencyWithdraw(address token, address recipient, uint256 amount) external onlyRole(OWNER_ROLE) {
        require(token != address(0), "Invalid token address");
        require(recipient != address(0), "Invalid recipient address");
        require(amount > 0, "Amount must be greater than 0");

        uint256 contractBalance = IERC20(token).balanceOf(address(this));
        require(contractBalance >= amount, "Insufficient balance");
        
        require(IERC20(token).transfer(recipient, amount), "Token transfer failed");
        emit EmergencyWithdraw(token, recipient, amount);
    }

    // Allow admin to rescue failed token swaps
    function recoverFailedSwap(address token, address recipient) external onlyRole(OWNER_ROLE) {
        require(token != address(0), "Invalid token address");
        require(recipient != address(0), "Invalid recipient address");
        
        uint256 amount = failedTokenSwaps[token];
        require(amount > 0, "No failed swaps for this token");
        
        failedTokenSwaps[token] = 0;
        require(IERC20(token).transfer(recipient, amount), "Token transfer failed");
        emit FailedSwapRecovered(token, recipient, amount);
    }

    // HELPER FUNCTIONS

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

    function _updatePlayerWager(uint256 epochId, address player, uint256 wagerAmount) internal {
        SettlementInfo storage settlement = settlementInfo[epochId];
        
        if (playerWagers[epochId][player] == 0) {
            // New player
            epochEligiblePlayers[epochId].push(player);
            settlement.playerCount++;
        }
        
        playerWagers[epochId][player] += wagerAmount;
    }
}