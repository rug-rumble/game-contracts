// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/Vault.sol";
import "../src/interfaces/IRugRumble.sol";
import "../src/swap-adapters/interfaces/IDexAdapter.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract DebugVaultScript is Script {
    // Addresses from the updated script
    Vault vault = Vault(0x953E0743fccd23848E0e6cB0Bc4C3fC594699b8b);
    IRugRumble rugRumble = IRugRumble(0x262Fd7A243e9335A733c00de471525D9FeE8Abdb);
    address wmonAddress = 0x760AfE86e5de5fa0Ee542fc7B7B713e1c5425701;
    address ownerAddress = 0x05d92948187e27dE115Bd79788AbE000a4BbB201;
    address dexAdapter = 0x840C602476ab5d9Ec515aBb86E5A0d7f30eb7B7C;
    
    // Meme token addresses
    address[] memeTokens = [
        0x0F0BDEbF0F83cD1EE3974779Bcb7315f9808c714,
        0xE0590015A873bF326bd645c3E1266d4db41C4E6B,
        0xfe140e1dCe99Be9F4F15d657CD9b7BF622270C50
    ];

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        
        // Get current epoch info
        uint256 lastEpochId = vault.lastEpochId();
        IVault.Epoch memory epoch = vault.getEpoch(lastEpochId);
        
        console.log("Last Epoch ID:", lastEpochId);
        console.log("Epoch State:", uint8(epoch.state));
        
        // Check for epoch games
        // uint256[] memory epochGames = vault.getEpochGames(lastEpochId);
        // console.log("Number of games in epoch:", epochGames.length);
        
        // // Check eligible players - simulation only
        // if (epochGames.length > 0) {
        //     uint256 playerCount = 0;
        //     address[] memory players = new address[](epochGames.length * 2); // Max possible players
            
        //     for (uint i = 0; i < epochGames.length && i < 5; i++) {
        //         IRugRumble.Game memory game = rugRumble.getGame(epochGames[i]);
        //         console.log("Game", i, "Token1:", game.token1);
        //         console.log("Game", i, "Token2:", game.token2);
                
        //         // Track unique players
        //         bool found1 = false;
        //         bool found2 = false;
                
        //         for (uint j = 0; j < playerCount; j++) {
        //             if (players[j] == game.player1) found1 = true;
        //             if (players[j] == game.player2) found2 = true;
        //         }
                
        //         if (!found1 && game.player1 != address(0)) {
        //             players[playerCount++] = game.player1;
        //         }
                
        //         if (!found2 && game.player2 != address(0)) {
        //             players[playerCount++] = game.player2;
        //         }
        //     }
            
        //     console.log("Estimated unique player count:", playerCount);
            
        //     if (playerCount == 0) {
        //         console.log("WARNING: No eligible players found in games!");
        //     }
        // }
        
        // // Check token balances
        for (uint i = 0; i < epoch.supportedTokens.length; i++) {
            address token = epoch.supportedTokens[i];
            uint256 balance = vault.epochDeposits(lastEpochId, token);
            // console.log("Epoch deposit for token", i, "(", token, "):", balance);
            
            uint256 contractBalance = IERC20(token).balanceOf(address(vault));
            console.log("Contract balance for token", i, ":", contractBalance);
            
            if (balance > 0 && contractBalance < balance) {
                console.log("WARNING: Contract balance < epoch deposit for token", i);
            }
        }
        
        // Only try to settle if epoch is FINISHED
        if (epoch.state == IVault.EpochState.FINISHED) {
            // Find token with highest balance as winning token
            address winningToken = 0x0F0BDEbF0F83cD1EE3974779Bcb7315f9808c714;

            console.log("Selected winning token:", winningToken);
            
            // Set DEX adapters for all token pairs
            for (uint i = 0; i < epoch.supportedTokens.length; i++) {
                address token = epoch.supportedTokens[i];
                if (token != winningToken) {
                    bytes32 pairHash = keccak256(abi.encodePacked(token, winningToken));
                    address adapter = vault.dexAdapters(pairHash);
                    
                    if (adapter == address(0)) {
                        console.log("Setting DEX adapter for", token, "to", winningToken);
                        vault.setDexAdapter(token, winningToken, dexAdapter);
                    }
                    
                    // Double-check it was set
                    adapter = vault.dexAdapters(pairHash);
                    console.log("DEX adapter now:", adapter);
                }
            }
            
            // Prepare swap data with thirdAsset (WMON)
            bytes memory swapData = abi.encode(wmonAddress);
            
            console.log("Attempting to settle vault with winning token:", winningToken);
            
            try vault.settleVault(swapData, winningToken, lastEpochId) {
                console.log("Vault settled successfully!");
            } catch Error(string memory reason) {
                console.log("Failed to settle vault:", reason);
            } catch (bytes memory) {
                console.log("Failed to settle vault with unknown error");
            }
        } else {
            console.log("Epoch not in FINISHED state, skipping settlement");
        }
        
        vm.stopBroadcast();
    }
}