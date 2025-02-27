# Deployment Instructions

This document provides instructions for deploying the RugRumble contracts using Foundry to different networks: local, testnet, and mainnet.

## Prerequisites

- Foundry installed (forge, anvil, and cast)
- `.env` file properly configured

## Environment File

Ensure you have a `.env` file set up with the correct values. You can use the `.env.example` file in the repository as a template. Copy the `.env.example` file and rename it to `.env`, then fill in the values for your specific deployment.

The `.env` file should contain:

```
PRIVATE_KEY=<your_private_key>
PROTOCOL_ADDRESS=<protocol_address>
OWNER_ADDRESS=<owner_address>
USDC_ADDRESS=<usdc_token_address>
UNISWAP_V2_ROUTER=<uniswap_v2_router_address>
IS_TESTNET=<true_or_false>
DEPLOY_TEST_TOKENS=<true_or_false>
```

## Deployment Steps

### 1. Local Foundry Network Deployment

1. Start a local Anvil node:
   ```
   anvil
   ```

2. Deploy the contracts:
   ```
   forge script script/DeployRugRumble.s.sol:DeployRugRumble --rpc-url local --broadcast
   ```

### 2. Testnet Deployment (Base Sepolia)

1. Ensure your `.env` file is configured with the correct testnet addresses.

2. Run the deployment script:
   ```
   forge script script/DeployRugRumble.s.sol:DeployRugRumble --rpc-url baseSepolia --broadcast --verify
   ```

### 3. Mainnet Deployment

1. Ensure your `.env` file is configured with the correct mainnet addresses.

2. Run the deployment script:
   ```
   forge script script/DeployRugRumble.s.sol:DeployRugRumble --rpc-url mainnet --broadcast --verify
   ```

## Post-Deployment

After successful deployment, the script will output the addresses of the deployed contracts. Make sure to save these addresses for future reference and integration.

## Verification

For testnet and mainnet deployments, the `--verify` flag is included to automatically verify the contracts on Etherscan (or the equivalent block explorer). Ensure you have set up the appropriate API keys in your Foundry configuration for this to work.

## Contract Addresses

After deployment, update this section with the deployed contract addresses:

- RugRumbleNFT: `<address>`
- UniswapV2Adapter: `<address>`
- RugRumble: `<address>`
- Vault: `<address>`

## Troubleshooting

- If you encounter RPC-related errors, make sure your RPC URL is correctly defined in the `foundry.toml` file.
- For verification issues, check that your Etherscan API key is correctly set in your Foundry configuration.
- If transactions fail, ensure your deployer address has sufficient ETH (or the network's native token) for gas fees.

## Security Considerations

- Ensure that the `PRIVATE_KEY` used for deployment is secure and not shared or committed to version control.
- After deployment, verify that the ownership of contracts has been correctly transferred to the intended `OWNER_ADDRESS`.
- Double-check all addresses (USDC, Uniswap Router, etc.) to ensure they are correct for the target network.

## Upgradeability

These contracts are not upgradeable. Any changes will require redeployment and migration of data/assets if applicable.

## Additional Notes

- The `IS_TESTNET` flag in the .env files determines whether testnet or mainnet URIs are used for NFT metadata.
- The `DEPLOY_TEST_TOKENS` flag, when set to `true`, will deploy two test ERC20 tokens (MEME1 and MEME2) and mint 10000 of each to the owner address. This is useful for testing on local or testnet environments.
- Make sure to update any frontend applications or integrations with the new contract addresses after deployment.

## Support

For any issues or questions regarding deployment, please contact the development team or open an issue in the project repository.