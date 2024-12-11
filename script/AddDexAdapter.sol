// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../src/RugRumble.sol";
import "../src/Vault.sol";

contract AddDexAdapters is Script {
    address constant WETH_ADDRESS = 0x4200000000000000000000000000000000000006;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address rugRumbleAddress = vm.envAddress("RUG_RUMBLE_ADDRESS");
        address vaultAddress = vm.envAddress("VAULT_ADDRESS");
        address dexAdapter = vm.envAddress("UNISWAP_V3_ADAPTER_ADDRESS");
        address brettAddress = vm.envAddress("BRETT_ADDRESS");
        address toshiAddress = vm.envAddress("TOSHI_ADDRESS");

        console.log("RugRumble:", rugRumbleAddress);
        console.log("Vault:", vaultAddress);
        console.log("DexAdapter:", dexAdapter);
        console.log("Brett:", brettAddress);
        console.log("Toshi:", toshiAddress);

        require(rugRumbleAddress != address(0), "RUG_RUMBLE_ADDRESS not set");
        require(vaultAddress != address(0), "VAULT_ADDRESS not set");
        require(dexAdapter != address(0), "UNISWAP_V3_ADAPTER_ADDRESS not set");
        require(brettAddress != address(0), "BRETT_ADDRESS not set");
        require(toshiAddress != address(0), "TOSHI_ADDRESS not set");

        vm.startBroadcast(deployerPrivateKey);

        RugRumble rugRumble = RugRumble(rugRumbleAddress);
        Vault vault = Vault(vaultAddress);

        // Set adapters for BRETT <-> TOSHI
        rugRumble.setDexAdapter(brettAddress, toshiAddress, dexAdapter);
        rugRumble.setDexAdapter(toshiAddress, brettAddress, dexAdapter);
        vault.setDexAdapter(brettAddress, toshiAddress, dexAdapter);
        vault.setDexAdapter(toshiAddress, brettAddress, dexAdapter);

        vm.stopBroadcast();
    }
}
