// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "../../src/interfaces/IRugRumble.sol";

contract MockRugRumble is IRugRumble {
    mapping(uint256 => Game) private games;

    function addSupportedToken(address _token) external override {
        // No-op in this mock
    }

    function removeSupportedToken(address _token) external override {
        // No-op in this mock
    }

    function setGame(
        uint256 gameId,
        address token1,
        address token2,
        uint256 wagerAmount1,
        uint256 wagerAmount2,
        uint256 epochId
    ) external override {
        games[gameId] = Game({
            player1: address(0),
            player2: address(0),
            token1: token1,
            token2: token2,
            wagerAmount1: wagerAmount1,
            wagerAmount2: wagerAmount2,
            isActive: true,
            winner: address(0),
            loser: address(0),
            epochId: epochId
        });
    }

    function depositForGame(uint256 gameId, address token) external override {
        // No-op in this mock
    }

    function endGame(uint256 gameId, address winner, bytes calldata data) external override {
        // No-op in this mock
    }

    function getGame(uint256 gameId) external view override returns (Game memory) {
        return games[gameId];
    }

    function refundGame(uint256 gameId) external override {
        // No-op in this mock
    }

    function updateVault(address _newVault) external override {
        // No-op in this mock
    }

    function updateOwner(address _newOwner) external override {
        // No-op in this mock
    }

    function setDexAdapter(address tokenA, address tokenB, address _dexAdapter) external override {
        // No-op in this mock
    }

    // Helper function to set the game details in tests
    function setMockGame(
        uint256 gameId,
        address player1,
        address player2,
        address token1,
        address token2,
        uint256 wagerAmount1,
        uint256 wagerAmount2,
        address winner,
        address loser,
        uint256 epochId
    ) external {
        games[gameId] = Game({
            player1: player1,
            player2: player2,
            token1: token1,
            token2: token2,
            wagerAmount1: wagerAmount1,
            wagerAmount2: wagerAmount2,
            isActive: true,
            winner: winner,
            loser: loser,
            epochId: epochId
        });
    }
}
