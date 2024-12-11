// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@uniswap/swap-router/contracts/interfaces/IV3SwapRouter.sol";
import {MockERC20} from "../utils/MockERC20.sol";

contract MockSwapRouter is IV3SwapRouter {
    uint256 public amountOut;

    constructor(uint256 _amountOut) {
        amountOut = _amountOut;
    }

    function exactInput(ExactInputParams calldata params) external payable override returns (uint256) {
        
        // Decode the path to extract the `toToken` address
        address toToken = extractToToken(params.path);
        
        // Mint `toToken` to the recipient
        MockERC20(toToken).mint(params.recipient, amountOut);

        return amountOut;
    }

    function extractToToken(bytes memory path) internal pure returns (address toToken) {
        // Uniswap V3 paths are packed as [address1][fee][address2][fee]...[fee][addressN]
        // The last 20 bytes of the path represent the `toToken`
        require(path.length >= 20, "MockSwapRouter: Invalid path length");

        assembly {
            // Load the last 20 bytes of the path
            toToken := and(mload(add(path, mload(path))), 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
        }
    }

    function exactInputSingle(ExactInputSingleParams calldata) external payable returns (uint256) {
        return amountOut;
    }

    function exactOutputSingle(ExactOutputSingleParams calldata) external payable returns (uint256 amountIn) {
        return amountOut;
    }

    function exactOutput(ExactOutputParams calldata) external payable returns (uint256 amountIn) {
        return amountOut;
    }

    function uniswapV3SwapCallback(
        int256,
        int256,
        bytes calldata
    ) external {}
}
