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
    // Functions
    function getEpoch(uint256 epochId) external view returns (Epoch memory);
    function getEpochGames(uint256 epochId) external view returns (uint256[] memory);
    function addSupportedToken(address tokenAddress) external;
    function updateGameContract(address gameContract) external;
    function setDexAdapter(
        address tokenA,
        address tokenB,
        address _dexAdapter
    ) external;
    function startEpoch(address[] memory tokenAddresses) external;
    function endEpoch(uint256 epochId) external;
    function depositFromGame(uint256 epochId, uint256 gameId, address token, uint256 amount) external;
    function settleVault(bytes calldata swapData, address winningTokenAddress, uint256 epochId) external;
    /// @notice Transfers ownership and all admin roles to a new owner
    /// @param newOwner The address of the new owner
    function transferOwnership(address newOwner) external;
}
