// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../swap-adapters/interfaces/IDexAdapter.sol";

interface IVault {

    enum EpochState { DEFAULT, STARTED, FINISHED, SETTLED }
    
    struct Epoch {
        uint256 epochId;
        address[] supportedTokens;
        EpochState state;
        address winningToken;
    }
    
    struct SettlementInfo {
        uint256 processedGameCount;
        uint256 playerCount;
        uint256 totalWagerAmount;
        bool isSwapCompleted;
        uint256 winningTokenBalance;
        bool isFullyDistributed;
    }
    
    // Events
    event EpochStarted(uint256 epochId, address[] tokenAddresses);
    event EpochFinished(uint256 epochId);
    event TokenAdded(address token, address admin);
    event DepositFromGame(uint256 epochId, uint256 gameId, address token, uint256 amount);
    event VaultSettled(uint256 epochId, address winningToken, uint256 totalDistributed);
    event SwapFailed(uint256 epochId, address token, uint256 amount);
    event TokenTransfered(uint256 epochId, address winnerToken, address player, uint256 amount);
    event TokenSwapped(uint256 epochId, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut);
    event EmergencyWithdraw(address indexed token, address indexed recipient, uint256 amount);
    event FailedSwapRecovered(address indexed token, address indexed recipient, uint256 amount);
    event SettlementInitialized(uint256 indexed epochId, address indexed winningToken);
    event GamesBatchProcessed(uint256 indexed epochId, uint256 processedGames, uint256 totalGames);
    event AllGamesProcessed(uint256 indexed epochId, uint256 playerCount, uint256 totalWagerAmount);
    event TokensSwapped(uint256 indexed epochId, address indexed winningToken, uint256 totalBalance);
    event DistributionBatchProcessed(uint256 indexed epochId, uint256 processedPlayers, uint256 totalPlayers);
    
    // View Functions
    function getEpoch(uint256 epochId) external view returns (Epoch memory);
    function getEpochGames(uint256 epochId) external view returns (uint256[] memory);
    function getEligiblePlayers(uint256 epochId) external view returns (address[] memory);
    function getPlayerWager(uint256 epochId, address player) external view returns (uint256);
    function getSettlementInfo(uint256 epochId) external view returns (SettlementInfo memory);
    
    // Admin Functions
    function addSupportedToken(address tokenAddress) external;
    function updateGameContract(address gameContract) external;
    function setDexAdapter(
        address tokenA,
        address tokenB,
        address _dexAdapter
    ) external;
    
    // Epoch Management
    function startEpoch(address[] memory tokenAddresses) external;
    function endEpoch(uint256 epochId) external;
    function depositFromGame(uint256 epochId, uint256 gameId, address token, uint256 amount) external;

    // New Batched Settlement Functions
    function initSettlement(uint256 epochId, address winningTokenAddress) external;
    function processGamesBatch(uint256 epochId, uint256 batchSize) external;
    function swapTokens(uint256 epochId, bytes calldata swapData) external;
    function distributeWinningsBatch(uint256 epochId, uint256 batchSize) external;
    
    // Failsafe Functions
    function emergencyWithdraw(address token, address recipient, uint256 amount) external;
    function recoverFailedSwap(address token, address recipient) external;
}