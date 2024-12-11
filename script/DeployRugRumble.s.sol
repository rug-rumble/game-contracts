// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/RugRumble.sol";
import "../src/Vault.sol";
import "../src/swap-adapters/UniswapV3Adapter.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "lib/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "../test/utils/MockERC20.sol";

contract DeployRugRumble is Script {
    uint256 deployerPrivateKey;
    address deployerAddress;
    address protocol;
    address owner;
    address uniswapV3Router;
    bool isTestnet;
    address[] initialSupportedTokens;

    // WETH on Base mainnet
    address constant wethAddress = 0x4200000000000000000000000000000000000006;

    function run() external {
        // Initialize environment variables
        deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        deployerAddress = vm.addr(deployerPrivateKey);
        protocol = vm.envAddress("PROTOCOL_ADDRESS");
        owner = vm.envAddress("OWNER_ADDRESS");
        uniswapV3Router = vm.envAddress("UNISWAP_V3_ROUTER");
        isTestnet = vm.envBool("IS_TESTNET");

        vm.startBroadcast(deployerPrivateKey);

        address brettAddress;
        address toshiAddress;

        // Deploy test tokens if testnet, otherwise use provided addresses
        if (isTestnet) {
            address meme1 = getOrDeployTestToken(
                "MEME1",
                "MEME1",
                "MEME1_ADDRESS"
            );
            address meme2 = getOrDeployTestToken(
                "MEME2",
                "MEME2",
                "MEME2_ADDRESS"
            );
            brettAddress = meme1;
            toshiAddress = meme2;
        } else {
            brettAddress = vm.envAddress("BRETT_ADDRESS");
            toshiAddress = vm.envAddress("TOSHI_ADDRESS");
        }

        initialSupportedTokens.push(brettAddress);
        initialSupportedTokens.push(toshiAddress);

        // Deploy contracts
        address dexAdapter = getOrDeployUniswapV3Adapter();
        address rugRumble = getOrDeployRugRumble();
        address vault = getOrDeployVault(rugRumble);

        // Update adapters for multi-hop routes via WETH
        // Set adapters for BRETT <-> WETH
        RugRumble(rugRumble).setDexAdapter(
            brettAddress,
            wethAddress,
            dexAdapter
        );
        RugRumble(rugRumble).setDexAdapter(
            wethAddress,
            brettAddress,
            dexAdapter
        );

        Vault(vault).setDexAdapter(brettAddress, wethAddress, dexAdapter);
        Vault(vault).setDexAdapter(wethAddress, brettAddress, dexAdapter);

        // Set adapters for TOSHI <-> WETH
        RugRumble(rugRumble).setDexAdapter(
            toshiAddress,
            wethAddress,
            dexAdapter
        );
        RugRumble(rugRumble).setDexAdapter(
            wethAddress,
            toshiAddress,
            dexAdapter
        );

        Vault(vault).setDexAdapter(toshiAddress, wethAddress, dexAdapter);
        Vault(vault).setDexAdapter(wethAddress, toshiAddress, dexAdapter);

        vm.stopBroadcast();

        // Log deployment information
        logDeploymentInfo(dexAdapter, rugRumble, vault);
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

    function getOrDeployUniswapV3Adapter() internal returns (address) {
        address existingAddress = vm.envOr(
            "UNISWAP_V3_ADAPTER_ADDRESS",
            address(0)
        );
        if (existingAddress != address(0)) {
            console.log("Using existing UniswapV3Adapter at:", existingAddress);
            return existingAddress;
        }
        UniswapV3Adapter dexAdapter = new UniswapV3Adapter(
            IV3SwapRouter(uniswapV3Router)
        );
        console.log("Deployed new UniswapV3Adapter at:", address(dexAdapter));
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
        console.log("UniswapV3Adapter deployed at:", dexAdapter);
        console.log("RugRumble deployed at:", rugRumble);
        console.log("Vault deployed at:", vault);
        console.log("API_KEY_BASESCAN:", vm.envString("API_KEY_BASESCAN"));
    }
}
