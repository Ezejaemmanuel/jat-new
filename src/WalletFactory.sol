// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {UserWallet} from "./UserWallet.sol";
import {console} from "forge-std/console.sol";
import {IUserWallet} from "./interfaces/IUserWallet.sol";

contract WalletFactory {
    error WalletFactory__WalletAlreadyExists();

    mapping(address user => address wallet) public userWallets;
    mapping(address wallet => address user) public walletToUser;
    address immutable i_entryPointAddress;
    uint256 public totalWallets;

    event WalletCreated(address indexed user, address wallet);

    constructor(address _entryPointAddress) {
        i_entryPointAddress = _entryPointAddress;
    }

    function createWallet() external returns (address) {
        if (userWallets[msg.sender] != address(0)) {
            console.log("Wallet already exists for:", msg.sender);
            revert WalletFactory__WalletAlreadyExists();
        }

        bytes32 salt = keccak256(abi.encodePacked(msg.sender));

        // Correctly encode constructor arguments with the bytecode
        bytes memory bytecode =
            abi.encodePacked(type(UserWallet).creationCode, abi.encode(msg.sender, i_entryPointAddress));

        address wallet = Create2.deploy(0, salt, bytecode);
        console.log("Wallet created at address:", wallet);
        totalWallets++;
        userWallets[msg.sender] = wallet;
        walletToUser[wallet] = msg.sender; // Add this line
        emit WalletCreated(msg.sender, wallet);

        return wallet;
    }

    // Getter functions

    /// @notice Gets the wallet address for a given user
    /// @param user The user address to look up
    /// @return The wallet address associated with the user
    function getUserWallet(address user) external view returns (address) {
        console.log("Getting wallet for user:", user);
        return userWallets[user];
    }

    /// @notice Gets the EntryPoint address
    /// @return The EntryPoint address
    function getEntryPointAddress() public view returns (address) {
        return i_entryPointAddress;
    }

    /// @notice Checks if an address is a user wallet and is available in the walletFactory
    /// @param _address The address to check
    /// @return True if the address is a user wallet and available, false otherwise
    function isValidUserWallet(address _address) public view returns (bool) {
        // Use the Address library to check if the address is a contract

        // Check if the address is available as a user wallet in the WalletFactory
        if (walletToUser[_address] != address(0)) {
            return true;
        } else {
            return false;
        }
    }

    /// @notice Gets the user address for a given wallet address
    /// @param _walletAddress The wallet address to look up
    /// @return The user address associated with the wallet, or address(0) if not found
    function getUserFromWallet(address _walletAddress) public view returns (address) {
        return walletToUser[_walletAddress];
    }

    /// @notice Checks if a wallet exists for a given user
    /// @param _user The user address to check
    /// @return True if a wallet exists for the user, false otherwise
    function hasWallet(address _user) public view returns (bool) {
        return userWallets[_user] != address(0);
    }

    /// @notice Gets the total number of wallets created
    /// @return The total number of wallets
    function getTotalWallets() public view returns (uint256) {
        return totalWallets;
    }
}
