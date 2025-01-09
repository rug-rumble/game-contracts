// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../src/RugRumble.sol";
import "../src/Vault.sol";

contract SetupDexAdapters is Script {
    address constant WETH_ADDRESS = 0x4200000000000000000000000000000000000006;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address rugRumbleAddress = vm.envAddress("RUG_RUMBLE_ADDRESS");
        address vaultAddress = vm.envAddress("VAULT_ADDRESS");
        address dexAdapter = vm.envAddress("UNISWAP_V3_ADAPTER_ADDRESS");
        address brettAddress = vm.envAddress("BRETT_ADDRESS");
        address toshiAddress = vm.envAddress("TOSHI_ADDRESS");

        console.log("Setting up DEX adapters with:");
        console.log("RugRumble:", rugRumbleAddress);
        console.log("Vault:", vaultAddress);
        console.log("DexAdapter:", dexAdapter);
        console.log("BRETT:", brettAddress);
        console.log("TOSHI:", toshiAddress);
        console.log("WETH:", WETH_ADDRESS);

        vm.startBroadcast(deployerPrivateKey);

        RugRumble rugRumble = RugRumble(rugRumbleAddress);
        Vault vault = Vault(vaultAddress);

        // Set direct adapters for BRETT <-> TOSHI
        rugRumble.setDexAdapter(brettAddress, toshiAddress, dexAdapter);
        rugRumble.setDexAdapter(toshiAddress, brettAddress, dexAdapter);
        vault.setDexAdapter(brettAddress, toshiAddress, dexAdapter);
        vault.setDexAdapter(toshiAddress, brettAddress, dexAdapter);

        // Set adapters for BRETT <-> WETH
        rugRumble.setDexAdapter(brettAddress, WETH_ADDRESS, dexAdapter);
        rugRumble.setDexAdapter(WETH_ADDRESS, brettAddress, dexAdapter);
        vault.setDexAdapter(brettAddress, WETH_ADDRESS, dexAdapter);
        vault.setDexAdapter(WETH_ADDRESS, brettAddress, dexAdapter);

        // Set adapters for TOSHI <-> WETH
        rugRumble.setDexAdapter(toshiAddress, WETH_ADDRESS, dexAdapter);
        rugRumble.setDexAdapter(WETH_ADDRESS, toshiAddress, dexAdapter);
        vault.setDexAdapter(toshiAddress, WETH_ADDRESS, dexAdapter);
        vault.setDexAdapter(WETH_ADDRESS, toshiAddress, dexAdapter);

        vm.stopBroadcast();

        console.log("Successfully set up all DEX adapters");
        console.log("- BRETT <-> TOSHI (direct)");
        console.log("- BRETT <-> WETH");
        console.log("- TOSHI <-> WETH");
    }
} 