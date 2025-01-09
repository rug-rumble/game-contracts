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
    address deploymentOwner;
    address finalOwner;
    address uniswapV3Router;
    bool isTestnet;
    bool forceNewDeployment;
    address[] initialSupportedTokens;

    // WETH on Base mainnet
    address constant wethAddress = 0x4200000000000000000000000000000000000006;

    function run() external {
        // Initialize environment variables
        deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        deployerAddress = vm.addr(deployerPrivateKey);
        protocol = vm.envAddress("PROTOCOL_ADDRESS");
        deploymentOwner = deployerAddress; // Use deployer as initial owner
        finalOwner = vm.envAddress("FINAL_OWNER_ADDRESS");
        uniswapV3Router = vm.envAddress("UNISWAP_V3_ROUTER");
        isTestnet = vm.envBool("IS_TESTNET");
        forceNewDeployment = vm.envBool("FORCE_NEW_DEPLOYMENT");

        console.log("Deployer address:", deployerAddress);
        console.log("Final owner address:", finalOwner);

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

        // Deploy or get existing contracts
        address dexAdapter = getOrDeployUniswapV3Adapter();
        address rugRumble = getOrDeployRugRumble();
        address vault = getOrDeployVault(rugRumble);

        // Only set DEX adapters if we're deploying new contracts or we're the owner
        bool canSetRugRumble = RugRumble(rugRumble).owner() == deployerAddress;
        bool canSetVault = Vault(vault).hasRole(Vault(vault).OWNER_ROLE(), deployerAddress);
        
        console.log("RugRumble owner:", RugRumble(rugRumble).owner());
        console.log("Can set RugRumble:", canSetRugRumble);
        console.log("Can set Vault:", canSetVault);
        
        bool canSetAdapters = canSetRugRumble && canSetVault;

        if (canSetAdapters) {
            // Set direct adapter for BRETT <-> TOSHI
            RugRumble(rugRumble).setDexAdapter(
                brettAddress,
                toshiAddress,
                dexAdapter
            );
            RugRumble(rugRumble).setDexAdapter(
                toshiAddress,
                brettAddress,
                dexAdapter
            );

            Vault(vault).setDexAdapter(brettAddress, toshiAddress, dexAdapter);
            Vault(vault).setDexAdapter(toshiAddress, brettAddress, dexAdapter);

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

            console.log("Set up DEX adapters for pairs:");
            console.log("- BRETT <-> TOSHI (direct)");
            console.log("- BRETT <-> WETH");
            console.log("- TOSHI <-> WETH");
        } else {
            console.log(
                "Warning: Skipping DEX adapter setup - deployer is not owner"
            );
        }

        vm.stopBroadcast();

        // Log deployment information
        logDeploymentInfo(dexAdapter, rugRumble, vault);
        if (!canSetAdapters) {
            console.log(
                "Note: DEX adapters were not set up. Please set them up using the owner account."
            );
        }

        // If this is a new deployment, transfer ownership to final owner
        if (forceNewDeployment && finalOwner != address(0)) {
            console.log("Transferring ownership to final owner...");
            this.transferAllOwnership(finalOwner, rugRumble, vault);
        }
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
        token.mint(deploymentOwner, 10000 * 10 ** 18);
        console.log("Deployed new %s token at:", name, address(token));
        return address(token);
    }

    function getOrDeployUniswapV3Adapter() internal returns (address) {
        address existingAddress = vm.envOr(
            "UNISWAP_V3_ADAPTER_ADDRESS",
            address(0)
        );
        if (existingAddress != address(0) && !forceNewDeployment) {
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
        if (existingAddress != address(0) && !forceNewDeployment) {
            console.log("Using existing RugRumble at:", existingAddress);
            RugRumble rugRumble = RugRumble(existingAddress);
            // Check if we need to update owner
            if (rugRumble.owner() != deploymentOwner && rugRumble.owner() == deployerAddress) {
                rugRumble.updateOwner(deploymentOwner);
            }
            return existingAddress;
        }

        RugRumble rugRumble = new RugRumble(
            protocol,
            deployerAddress
        );

        // Add supported tokens to RugRumble
        for (uint256 i = 0; i < initialSupportedTokens.length; i++) {
            rugRumble.addSupportedToken(initialSupportedTokens[i]);
        }

        // If deployer is not the intended owner, transfer ownership
        if (deploymentOwner != deployerAddress) {
            rugRumble.updateOwner(deploymentOwner);
        }

        console.log("Deployed new RugRumble at:", address(rugRumble));
        return address(rugRumble);
    }

    function getOrDeployVault(address rugRumble) internal returns (address) {
        address existingAddress = vm.envOr("VAULT_ADDRESS", address(0));
        if (existingAddress != address(0) && !forceNewDeployment) {
            console.log("Using existing Vault at:", existingAddress);
            // If using existing vault, check if we need to transfer ownership
            Vault vault = Vault(existingAddress);
            if (
                vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), deployerAddress) &&
                deploymentOwner != deployerAddress
            ) {
                vault.transferOwnership(deploymentOwner);
            }
            return existingAddress;
        }

        Vault vault = new Vault(
            address(rugRumble),
            initialSupportedTokens,
            deployerAddress // deployerAddress as initial admin
        );

        // Transfer ownership to the intended owner if different from deployer
        if (deploymentOwner != deployerAddress) {
            vault.transferOwnership(deploymentOwner);
        }

        // Update vault address in RugRumble
        RugRumble(rugRumble).updateVault(address(vault));

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

    function transferAllOwnership(
        address newOwner,
        address rugRumbleAddress,
        address vaultAddress
    ) external {
        require(newOwner != address(0), "New owner cannot be zero address");
        require(rugRumbleAddress != address(0), "RugRumble address cannot be zero");
        require(vaultAddress != address(0), "Vault address cannot be zero");

        deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        deployerAddress = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // Transfer RugRumble ownership
        RugRumble rugRumble = RugRumble(rugRumbleAddress);
        if (rugRumble.owner() == deployerAddress) {
            console.log("Transferring RugRumble ownership to:", newOwner);
            rugRumble.updateOwner(newOwner);
        } else {
            console.log("Cannot transfer RugRumble ownership - not current owner");
        }

        // Transfer Vault ownership
        Vault vault = Vault(vaultAddress);
        if (vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), deployerAddress)) {
            console.log("Transferring Vault ownership to:", newOwner);
            vault.transferOwnership(newOwner);
        } else {
            console.log("Cannot transfer Vault ownership - not current admin");
        }

        vm.stopBroadcast();

        // Log final ownership status
        console.log("Final RugRumble owner:", rugRumble.owner());
        console.log("Final Vault admin:", vault.getRoleMember(vault.DEFAULT_ADMIN_ROLE(), 0));
    }
}
