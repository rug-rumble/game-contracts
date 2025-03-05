// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/RugRumble.sol";
import "../src/Vault.sol";
import "../src/swap-adapters/UniswapV2Adapter.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "../test/utils/MockERC20.sol";

contract DeployRugRumble is Script {
    uint256 deployerPrivateKey;
    address deployerAddress;
    address protocol;
    address owner;
    address uniswapV2Router;
    bool isTestnet;
    bool deployTestTokens;
    address[] initialSupportedTokens;

    // WETH on Base mainnet
    address constant wmonAddress = 0x760AfE86e5de5fa0Ee542fc7B7B713e1c5425701;

    function run() external {
        // Initialize environment variables
        deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        deployerAddress = vm.addr(deployerPrivateKey);
        protocol = vm.envAddress("PROTOCOL_ADDRESS");
        owner = vm.envAddress("OWNER_ADDRESS");
        uniswapV2Router = vm.envAddress("UNISWAP_V2_ROUTER");
        isTestnet = vm.envBool("IS_TESTNET");
        deployTestTokens = vm.envBool("DEPLOY_TEST_TOKENS");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy or get meme tokens
        if (deployTestTokens) {
            // Deploy test tokens if deployTestTokens flag is set
            for (uint256 i = 0; i < 3; i++) {
                string memory tokenNumber = vm.toString(i + 1);
                string memory name = string.concat("MEME", tokenNumber);
                string memory envVar = string.concat("MEME", tokenNumber, "_ADDRESS");
                
                address memeToken = getOrDeployTestToken(name, name, envVar);
                initialSupportedTokens.push(memeToken);
            }
        } else {
            // Use provided meme addresses
            string memory memeAddressesRaw = vm.envString("MEME_ADDRESSES");
            initialSupportedTokens = parseAddressArray(memeAddressesRaw);
            require(initialSupportedTokens.length > 0, "No meme addresses provided");
        }

        // Deploy contracts
        address dexAdapter = getOrDeployUniswapV2Adapter();
        address rugRumble = getOrDeployRugRumble();
        address vault = getOrDeployVault(rugRumble);

        // Update adapters for multi-hop routes via WETH for all tokens
        for (uint256 i = 0; i < initialSupportedTokens.length; i++) {
            address memeToken = initialSupportedTokens[i];
            
            // Set adapters for MemeToken <-> WETH
            RugRumble(rugRumble).setDexAdapter(memeToken, wmonAddress, dexAdapter);
            RugRumble(rugRumble).setDexAdapter(wmonAddress, memeToken, dexAdapter);
            Vault(vault).setDexAdapter(memeToken, wmonAddress, dexAdapter);
            Vault(vault).setDexAdapter(wmonAddress, memeToken, dexAdapter);
        }

        // Update adapters for meme routes via WETH for all tokens
        for (uint i = 0; i < initialSupportedTokens.length; i++) {
            for (uint j = i + 1; j < initialSupportedTokens.length; j++) {
                // Set adapters for token0 <-> token1 and vice versa
                RugRumble(rugRumble).setDexAdapter(initialSupportedTokens[i], initialSupportedTokens[j], dexAdapter);
                RugRumble(rugRumble).setDexAdapter(initialSupportedTokens[j], initialSupportedTokens[i], dexAdapter);
                Vault(vault).setDexAdapter(initialSupportedTokens[i], initialSupportedTokens[j], dexAdapter);
                Vault(vault).setDexAdapter(initialSupportedTokens[j], initialSupportedTokens[i], dexAdapter);
            }
        }

        vm.stopBroadcast();

        // Log deployment information
        logDeploymentInfo(dexAdapter, rugRumble, vault);
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

    function getOrDeployTestToken(
        string memory name,
        string memory symbol,
        string memory envVar
    ) internal returns (address) {
        address existingAddress = vm.envOr(envVar, address(0));
        if (existingAddress != address(0)) {
            console.log("Using existing %s token at:", name, existingAddress);
            return existingAddress;
        }
        MockERC20 token = new MockERC20(name, symbol);
        token.mint(owner, 10000 * 10 ** 18);
        console.log("Deployed new %s token at:", name, address(token));
        return address(token);
    }

    function getOrDeployUniswapV2Adapter() internal returns (address) {
        address existingAddress = vm.envOr(
            "UNISWAP_V2_ADAPTER_ADDRESS",
            address(0)
        );
        if (existingAddress != address(0)) {
            console.log("Using existing UniswapV2Adapter at:", existingAddress);
            return existingAddress;
        }
        UniswapV2Adapter dexAdapter = new UniswapV2Adapter(
            IUniswapV2Router02(uniswapV2Router)
        );
        console.log("Deployed new UniswapV2Adapter at:", address(dexAdapter));
        return address(dexAdapter);
    }

    function getOrDeployRugRumble() internal returns (address) {
        address existingAddress = vm.envOr("RUG_RUMBLE_ADDRESS", address(0));
        if (existingAddress != address(0)) {
            console.log("Using existing RugRumble at:", existingAddress);
            return existingAddress;
        }
        RugRumble rugRumble = new RugRumble(
            protocol,
            deployerAddress // Assuming deployerAddress as owner
        );

        // Add supported tokens to RugRumble
        for (uint256 i = 0; i < initialSupportedTokens.length; i++) {
            rugRumble.addSupportedToken(initialSupportedTokens[i]);
        }

        console.log("Deployed new RugRumble at:", address(rugRumble));
        return address(rugRumble);
    }

    function getOrDeployVault(address rugRumble) internal returns (address) {
        address existingAddress = vm.envOr("VAULT_ADDRESS", address(0));
        if (existingAddress != address(0)) {
            console.log("Using existing Vault at:", existingAddress);
            return existingAddress;
        }

        Vault vault = new Vault(
            address(rugRumble),
            initialSupportedTokens,
            deployerAddress // Assuming deployerAddress as default admin
        );

        // Grant roles and transfer ownership
        bytes32 epochControllerRole = vault.EPOCH_CONTROLLER_ROLE();
        bytes32 ownerRole = vault.OWNER_ROLE();
        vault.grantRole(epochControllerRole, owner);
        vault.grantRole(ownerRole, owner);
        vault.grantRole(vault.DEFAULT_ADMIN_ROLE(), owner);
        vault.revokeRole(vault.DEFAULT_ADMIN_ROLE(), deployerAddress);

        // Update vault address in RugRumble
        RugRumble(rugRumble).updateVault(address(vault));

        // Transfer ownership of RugRumble to the intended owner
        RugRumble(rugRumble).updateOwner(owner);

        console.log("Deployed new Vault at:", address(vault));
        return address(vault);
    }

    function logDeploymentInfo(
        address dexAdapter,
        address rugRumble,
        address vault
    ) internal view {
        console.log("Network:", isTestnet ? "Testnet" : "Mainnet");
        console.log("UniswapV2Adapter deployed at:", dexAdapter);
        console.log("RugRumble deployed at:", rugRumble);
        console.log("Vault deployed at:", vault);
        console.log("Number of supported tokens:", initialSupportedTokens.length);
        for (uint256 i = 0; i < initialSupportedTokens.length; i++) {
            console.log("Token", i + 1, "address:", initialSupportedTokens[i]);
        }
        console.log("API_KEY_BASESCAN:", vm.envString("API_KEY_BASESCAN"));
    }
}