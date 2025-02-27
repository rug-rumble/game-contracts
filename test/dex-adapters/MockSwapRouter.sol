// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {MockERC20} from "../utils/MockERC20.sol";

contract MockSwapRouter {
    uint256 public amountOut;

    constructor(uint256 _amountOut) {
        amountOut = _amountOut;
    }

    function swapExactTokensForTokens(
        uint,  // amountIn
        uint,  // amountOutMin
        address[] calldata path,
        address to,
        uint  // deadline
    ) external returns (uint[] memory amounts) {
        require(path.length >= 2, "MockSwapRouter: Invalid path length");
        
        // Mint the output token to the recipient
        address toToken = path[path.length - 1];
        MockERC20(toToken).mint(to, amountOut);

        // Return amounts array with input and output amounts
        amounts = new uint[](path.length);
        amounts[0] = amountOut;  // Using amountOut as amountIn for simplicity
        amounts[path.length - 1] = amountOut;
        
        // Fill intermediate amounts if it's a multi-hop swap
        for (uint i = 1; i < path.length - 1; i++) {
            amounts[i] = amountOut / (path.length - i);
        }

        return amounts;
    }
}