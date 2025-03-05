// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../src/RugRumble.sol";
import "../src/Vault.sol";

contract AddDexAdapters is Script {
    address constant WETH_ADDRESS = 0x760AfE86e5de5fa0Ee542fc7B7B713e1c5425701;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address rugRumbleAddress = vm.envAddress("RUG_RUMBLE_ADDRESS");
        address vaultAddress = vm.envAddress("VAULT_ADDRESS");
        address dexAdapter = vm.envAddress("UNISWAP_V2_ADAPTER_ADDRESS");
        address[] memory memeAddresses = parseAddressArray(vm.envString("MEME_ADDRESSES"));

        console.log("RugRumble:", rugRumbleAddress);
        console.log("Vault:", vaultAddress);
        console.log("DexAdapter:", dexAdapter);
        console.log("Number of meme tokens:", memeAddresses.length);

        require(rugRumbleAddress != address(0), "RUG_RUMBLE_ADDRESS not set");
        require(vaultAddress != address(0), "VAULT_ADDRESS not set");
        require(dexAdapter != address(0), "UNISWAP_V2_ADAPTER_ADDRESS not set");
        require(memeAddresses.length > 0, "MEME_ADDRESSES array is empty");

        vm.startBroadcast(deployerPrivateKey);

        RugRumble rugRumble = RugRumble(rugRumbleAddress);
        Vault vault = Vault(vaultAddress);

        // Set adapters for all possible token pairs
        for (uint i = 0; i < memeAddresses.length; i++) {
            for (uint j = i + 1; j < memeAddresses.length; j++) {
                // Set adapters for token0 <-> token1 and vice versa
                rugRumble.setDexAdapter(memeAddresses[i], memeAddresses[j], dexAdapter);
                rugRumble.setDexAdapter(memeAddresses[j], memeAddresses[i], dexAdapter);
                vault.setDexAdapter(memeAddresses[i], memeAddresses[j], dexAdapter);
                vault.setDexAdapter(memeAddresses[j], memeAddresses[i], dexAdapter);
            }
        }

        vm.stopBroadcast();
    }

    function parseAddressArray(string memory addressesRaw) internal pure returns (address[] memory) {
        // Split the comma-separated string of addresses
        bytes memory addressesBytes = bytes(addressesRaw);
        uint256 count = 1;
        for (uint256 i = 0; i < addressesBytes.length; i++) {
            if (addressesBytes[i] == ",") count++;
        }
        
        address[] memory addresses = new address[](count);
        uint256 addressIndex = 0;
        uint256 startIndex = 0;
        
        for (uint256 i = 0; i < addressesBytes.length; i++) {
            if (addressesBytes[i] == "," || i == addressesBytes.length - 1) {
                uint256 endIndex = i == addressesBytes.length - 1 ? i + 1 : i;
                bytes memory addressBytes = new bytes(endIndex - startIndex);
                for (uint256 j = startIndex; j < endIndex; j++) {
                    addressBytes[j - startIndex] = addressesBytes[j];
                }
                addresses[addressIndex] = vm.parseAddress(string(addressBytes));
                addressIndex++;
                startIndex = i + 1;
            }
        }
        
        return addresses;
    }
}
