// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {WalletFactory} from "../src/WalletFactory.sol";
import {UserWallet} from "../src/UserWallet.sol";
import {console} from "forge-std/console.sol";
import {IEntryPoint} from "../lib/account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {DeployScript} from "../script/DeployScript.s.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";

contract TestTarget {
    uint256 public value;

    function setValue(uint256 _value) external {
        value = _value;
    }
}

contract WalletFactoryTest is Test {
    WalletFactory walletFactory;
    HelperConfig helperConfig;
    address user = makeAddr("user");
    IEntryPoint entryPoint;

    function setUp() public {
        DeployScript deployer = new DeployScript();
        (walletFactory, helperConfig) = deployer.run();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        entryPoint = IEntryPoint(config.entryPoint);
        console.log("WalletFactory deployed");
    }

    function testCreateWallet() public {
        console.log("Testing wallet creation for user:", user);

        // User creates a wallet
        vm.prank(user);
        address walletAddress = walletFactory.createWallet();
        console.log("Wallet created for user:", user, "at address:", walletAddress);

        // Verify that the wallet is created and stored in userWallets mapping
        address storedWalletAddress = walletFactory.getUserWallet(user);
        console.log("Stored wallet address for user:", user, "is:", storedWalletAddress);

        assertEq(walletAddress, storedWalletAddress, "Wallet address mismatch");

        // Verify that the wallet is a UserWallet contract
        bool isContract = walletAddress.code.length > 0;
        console.log("Is the wallet address a contract?", isContract);
        assertTrue(isContract, "Wallet address is not a contract");

        // Convert the address to a payable address before casting
        address payable walletAddressPayable = payable(walletAddress);

        // Verify the owner of the UserWallet
        UserWallet userWallet = UserWallet(walletAddressPayable);
        address walletOwner = userWallet.owner();
        console.log("Owner of the UserWallet is:", walletOwner);
        assertEq(walletOwner, user, "Owner of the UserWallet is incorrect");
    }

    function testUserWalletInitialization() public {
        // Deploy a new wallet
        vm.prank(user);
        address walletAddress = walletFactory.createWallet();

        // Cast the wallet address to UserWallet
        UserWallet userWallet = UserWallet(payable(walletAddress));

        // Check if the owner is set correctly
        address walletOwner = userWallet.owner();
        assertEq(walletOwner, user, "UserWallet owner is not set correctly");

        // Check if the EntryPoint is set correctly
        address entryPointAddress = userWallet.getEntryPoint();
        assertEq(entryPointAddress, address(entryPoint), "EntryPoint address is not set correctly");

        // Check if the wallet can receive ETH
        uint256 initialBalance = address(userWallet).balance;
        vm.deal(address(this), 1 ether);

        // Use call instead of transfer
        (bool success,) = address(userWallet).call{value: 1 ether}("");
        require(success, "Failed to send Ether");

        uint256 newBalance = address(userWallet).balance;
        assertEq(newBalance, initialBalance + 1 ether, "UserWallet did not receive ETH correctly");

        // Deploy TestTarget contract
        TestTarget testTarget = new TestTarget();

        // Prepare the calldata for setting a value
        bytes memory setValueCalldata = abi.encodeWithSignature("setValue(uint256)", 42);

        // Execute the transaction through the UserWallet
        vm.prank(user);
        userWallet.execute(address(testTarget), 0, setValueCalldata);

        // Check if the value was set correctly
        assertEq(testTarget.value(), 42, "TestTarget value was not set correctly");

        console.log("UserWallet initialization tests passed");
    }
}
