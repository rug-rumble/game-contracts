// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../src/RugRumbleNFT.sol";
import "./utils/MockERC20.sol";

contract RugRumbleNFTTest is Test {
    RugRumbleNFT public rugRumbleNFT;
    MockERC20 public usdcToken;

    address public constant OWNER = address(0x123);
    address public constant PLAYER = address(0x456);
    address public constant PROTOCOL = address(0x789);
    uint256 public constant INITIAL_BALANCE = 1000 * 10 ** 6; // 1000 USDC

    function setUp() public {
        usdcToken = new MockERC20("Mock USDC", "USDC");
        vm.startPrank(OWNER);
        rugRumbleNFT = new RugRumbleNFT(
            "https://example.com/token/",
            OWNER,
            address(usdcToken),
            PROTOCOL
        );
        vm.stopPrank();

        usdcToken.mint(PLAYER, INITIAL_BALANCE);
        vm.prank(PLAYER);
        usdcToken.approve(address(rugRumbleNFT), type(uint256).max);

        // Verify initial setup
        assertEq(rugRumbleNFT.owner(), OWNER, "Owner should be set correctly");
        assertEq(
            rugRumbleNFT.protocolAddress(),
            PROTOCOL,
            "Protocol address should be set correctly"
        );
    }

    function testFreeMint() public {
        // Setup: Admin add a deck config for free minting
        IRugRumbleNFT.CardConfig[]
            memory freeConfig = new IRugRumbleNFT.CardConfig[](5);
        freeConfig[0] = IRugRumbleNFT.CardConfig(
            IRugRumbleNFT.Rarity.COMMON,
            2,
            1
        );
        freeConfig[1] = IRugRumbleNFT.CardConfig(
            IRugRumbleNFT.Rarity.COMMON,
            1,
            2
        );
        freeConfig[2] = IRugRumbleNFT.CardConfig(
            IRugRumbleNFT.Rarity.RARE,
            1,
            10
        );
        freeConfig[3] = IRugRumbleNFT.CardConfig(
            IRugRumbleNFT.Rarity.EPIC,
            1,
            100
        );

        vm.startPrank(OWNER);
        rugRumbleNFT.addMintConfig(freeConfig, false, 0);
        rugRumbleNFT.freeMint(PLAYER, 0);
        vm.stopPrank();

        // Check balances
        assertEq(
            rugRumbleNFT.balanceOf(PLAYER, 1),
            2,
            "Should have 2 Common NFTs (ID 1)"
        );
        assertEq(
            rugRumbleNFT.balanceOf(PLAYER, 2),
            1,
            "Should have 1 Common NFT (ID 2)"
        );
        assertEq(
            rugRumbleNFT.balanceOf(PLAYER, 10),
            1,
            "Should have 1 Rare NFT"
        );
        assertEq(
            rugRumbleNFT.balanceOf(PLAYER, 100),
            1,
            "Should have 1 Epic NFT"
        );
        assertEq(
            rugRumbleNFT.balanceOf(PLAYER, 1000),
            0,
            "Should have 0 Legendary NFT"
        );
    }

    function testPaidMint() public {
        IRugRumbleNFT.CardConfig[]
            memory paidConfig = new IRugRumbleNFT.CardConfig[](6);
        paidConfig[0] = IRugRumbleNFT.CardConfig(
            IRugRumbleNFT.Rarity.COMMON,
            2,
            1
        );
        paidConfig[1] = IRugRumbleNFT.CardConfig(
            IRugRumbleNFT.Rarity.COMMON,
            1,
            2
        );
        paidConfig[2] = IRugRumbleNFT.CardConfig(
            IRugRumbleNFT.Rarity.RARE,
            1,
            10
        );
        paidConfig[3] = IRugRumbleNFT.CardConfig(
            IRugRumbleNFT.Rarity.RARE,
            1,
            11
        );
        paidConfig[4] = IRugRumbleNFT.CardConfig(
            IRugRumbleNFT.Rarity.EPIC,
            1,
            100
        );
        paidConfig[5] = IRugRumbleNFT.CardConfig(
            IRugRumbleNFT.Rarity.LEGENDARY,
            1,
            1000
        );

        uint256 packPrice = 100 * 10 ** 6; // 100 USDC

        vm.startPrank(OWNER);
        rugRumbleNFT.addMintConfig(paidConfig, true, packPrice);
        vm.stopPrank();

        vm.startPrank(PLAYER);
        usdcToken.approve(address(rugRumbleNFT), packPrice);
        vm.stopPrank();

        uint256 playerBalanceBefore = usdcToken.balanceOf(PLAYER);
        uint256 protocolBalanceBefore = usdcToken.balanceOf(PROTOCOL);

        vm.startPrank(OWNER);
        rugRumbleNFT.mint(PLAYER, 0);
        vm.stopPrank();

        uint256 playerBalanceAfter = usdcToken.balanceOf(PLAYER);
        uint256 protocolBalanceAfter = usdcToken.balanceOf(PROTOCOL);

        // Check USDC balances
        assertEq(
            playerBalanceAfter,
            playerBalanceBefore - packPrice,
            "Player balance should be reduced by pack price"
        );
        assertEq(
            protocolBalanceAfter,
            protocolBalanceBefore + packPrice,
            "Protocol balance should increase by pack price"
        );

        // Check NFT balances
        assertEq(
            rugRumbleNFT.balanceOf(PLAYER, 1),
            2,
            "Should have 2 Common NFTs (ID 1)"
        );
        assertEq(
            rugRumbleNFT.balanceOf(PLAYER, 2),
            1,
            "Should have 1 Common NFT (ID 2)"
        );
        assertEq(
            rugRumbleNFT.balanceOf(PLAYER, 10),
            1,
            "Should have 1 Rare NFT (ID 10)"
        );
        assertEq(
            rugRumbleNFT.balanceOf(PLAYER, 11),
            1,
            "Should have 1 Rare NFT (ID 11)"
        );
        assertEq(
            rugRumbleNFT.balanceOf(PLAYER, 100),
            1,
            "Should have 1 Epic NFT"
        );
        assertEq(
            rugRumbleNFT.balanceOf(PLAYER, 1000),
            1,
            "Should have 1 Legendary NFT"
        );
    }

    function testLockAndUnlockNFTs() public {}
}
