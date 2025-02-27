// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "../../src/swap-adapters/UniswapV2Adapter.sol";
import {MockERC20} from "../utils/MockERC20.sol";
import "forge-std/Test.sol";
import "./MockSwapRouter.sol";

contract UniswapV2AdapterTest is Test {
    UniswapV2Adapter adapter;
    MockSwapRouter mockRouter;
    MockERC20 fromToken;
    MockERC20 toToken;
    address recipient = address(1);
    uint256 amountIn = 100;
    uint256 amountOutMin = 0;
    uint256 mockOutputAmount = 120;

    function setUp() public {
        fromToken = new MockERC20("Token A", "TKA");
        toToken = new MockERC20("Token B", "TKB");
        // Initialize the mock router with a fixed return amount
        mockRouter = new MockSwapRouter(mockOutputAmount);
        adapter = new UniswapV2Adapter(IUniswapV2Router02(address(mockRouter)));
    }

    function testSwapExactInput_Success() public {
        // Prepare swap data
        bytes memory data = abi.encode(address(0));

        // Mint tokens to the adapter
        fromToken.mint(address(this), amountIn);
        fromToken.approve(address(adapter), amountIn);

        // Call the adapter's swapExactInput method
        uint256 amountOut = adapter.swapExactInput(
            address(fromToken),
            address(toToken),
            amountIn,
            amountOutMin,
            recipient,
            data
        );

        // Assert the returned amountOut
        assertEq(amountOut, mockOutputAmount);
        // Assert the balance of toToken in recipient is equal to the output amount
        assertEq(toToken.balanceOf(recipient), mockOutputAmount);
    }

    function testSwapExactInput_Multihop() public {
        // Prepare swap data for a multihop swap
        bytes memory data = abi.encode(address(4)); // Third asset

        // Mint tokens to the adapter
        fromToken.mint(address(this), amountIn);
        fromToken.approve(address(adapter), amountIn);
        
        // Call the adapter's swapExactInput method
        uint256 amountOut = adapter.swapExactInput(
            address(fromToken),
            address(toToken),
            amountIn,
            amountOutMin,
            recipient,
            data
        );

        // Assert the returned amountOut
        assertEq(amountOut, mockOutputAmount);
        // Assert the balance of toToken in recipient is equal to the output amount
        assertEq(toToken.balanceOf(recipient), mockOutputAmount);
    }
}
