// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../../src/swap-adapters/interfaces/IDexAdapter.sol";
import {MockERC20} from "../utils/MockERC20.sol";

contract MockUniswapV2Adapter is IDexAdapter {
    uint256 public amountOut;

    constructor(uint256 _amountOut) {
        amountOut = _amountOut;
    }

    function swapExactInput(
        address,
        address toToken,
        uint256,
        uint256,
        address recipient,
        bytes calldata
    ) external override returns (uint256) {
        // Simulate minting the toToken with the amountOut quantity
        MockERC20(address(toToken)).mint(recipient, amountOut);
        return amountOut;
    }
}
