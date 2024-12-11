// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "@uniswap/swap-router/contracts/interfaces/IV3SwapRouter.sol";
import "./interfaces/IDexAdapter.sol";

contract UniswapV3Adapter is IDexAdapter {
    IV3SwapRouter public swapRouter;

    constructor(IV3SwapRouter _swapRouter) {
        swapRouter = _swapRouter;
    }

    /**
     * @notice Swap an exact amount of tokens for another token. This method should be called from
     * another smart contract and it assumes the caller transfer the tokens to this contract before 
     * calling this method. If the swap failed, the tokens are returned to the caller contract.
     * @param fromToken The token to swap from
     * @param toToken The token to swap to
     * @param amountIn The amount of `fromToken` to swap
     * @param amountOutMin The minimum amount of `toToken` to receive
     * @param recipient The address to receive the swapped tokens
     * @param data Additional data with swap parameters
     * @return amountOut The amount of `toToken` received
     */
    function swapExactInput(
        address fromToken,
        address toToken,
        uint256 amountIn,
        uint256 amountOutMin,
        address recipient,
        bytes calldata data
    ) external override returns (uint256 amountOut) {
        require(IERC20(fromToken).allowance(msg.sender, address(this)) >= amountIn, "Not enough approval");
        // Decode the `data` parameter
        (uint24 feeTier, address thirdAsset) = abi.decode(data, (uint24, address));

        bytes memory path;
        if (thirdAsset == address(0)) {
            // Direct swap (no third asset provided)
            path = abi.encodePacked(
                fromToken,
                feeTier,
                toToken
            );
        } else {
            // Multihop swap (third asset provided)
            path = abi.encodePacked(
                fromToken,
                feeTier,
                thirdAsset,
                feeTier,
                toToken
            );
        }

        // Set up the swap parameters
        IV3SwapRouter.ExactInputParams memory params = IV3SwapRouter.ExactInputParams({
            path: path,
            recipient: recipient,
            amountIn: amountIn,
            amountOutMinimum: amountOutMin
        });

        // Pull tokens from the caller
        IERC20(fromToken).transferFrom(msg.sender, address(this), amountIn);

        // Approve the Router
        IERC20(fromToken).approve(address(swapRouter), amountIn);

        // Perform the swap
        try swapRouter.exactInput(params) returns (uint256 _amountOut) {
            amountOut = _amountOut;
        } catch {
            // If swap fails, return the tokens to the sender
            IERC20(fromToken).transfer(msg.sender, amountIn);
            
            // Revert the call. Handle this in the caller assuming the tokens were sent back to the calling contract
            revert("UniswapV3Adapter: swapExactInput failed");
        }
    }
}
