// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IDexAdapter {
    function swapExactInput(
        address fromToken,
        address toToken,
        uint256 amountIn,
        uint256 amountOutMin,
        address recipient,
        bytes calldata data
    ) external returns (uint256 amountOut);
}
