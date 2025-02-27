// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "./interfaces/IDexAdapter.sol";

contract UniswapV2Adapter is IDexAdapter {
    IUniswapV2Router02 public swapRouter;
    
    event SwapAttempt(address fromToken, address toToken, uint256 amountIn, address[] path);
    event TokenApproval(address token, uint256 amount);
    event SwapResult(bool success, uint256 amountOut);

    constructor(IUniswapV2Router02 _swapRouter) {
        swapRouter = _swapRouter;
    }

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
        (address thirdAsset) = abi.decode(data, (address));

        // Create the path array for V2 router
        address[] memory path;
        if (thirdAsset == address(0)) {
            path = new address[](2);
            path[0] = fromToken;
            path[1] = toToken;
        } else {
            path = new address[](3);
            path[0] = fromToken;
            path[1] = thirdAsset;
            path[2] = toToken;
        }

        emit SwapAttempt(fromToken, toToken, amountIn, path);

        // Pull tokens from the caller
        IERC20(fromToken).transferFrom(msg.sender, address(this), amountIn);

        // Approve the Router
        IERC20(fromToken).approve(address(swapRouter), amountIn);
        emit TokenApproval(fromToken, amountIn);

        // Set deadline to current block timestamp
        uint256 deadline = block.timestamp;

        // Perform the swap
        try swapRouter.swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            path,
            recipient,
            deadline
        ) returns (uint256[] memory amounts) {
            amountOut = amounts[amounts.length - 1];
            emit SwapResult(true, amountOut);
        } catch Error(string memory reason) {
            // If swap fails, return the tokens to the sender
            IERC20(fromToken).transfer(msg.sender, amountIn);
            emit SwapResult(false, 0);
            revert(string(abi.encodePacked("UniswapV2Adapter: ", reason)));
        } catch {
            // If swap fails with no reason, return the tokens to the sender
            IERC20(fromToken).transfer(msg.sender, amountIn);
            emit SwapResult(false, 0);
            revert("UniswapV2Adapter: swapExactInput failed");
        }
    }
}