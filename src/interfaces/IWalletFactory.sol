// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IWalletFactory {
    error WalletFactory__WalletAlreadyExists();

    event WalletCreated(address indexed user, address wallet);

    function createWallet() external returns (address);

    function getUserWallet(address user) external view returns (address);

    function getEntryPointAddress() external view returns (address);

    function isValidUserWallet(address _address) external view returns (bool);

    function getUserFromWallet(address _walletAddress) external view returns (address);

    function hasWallet(address _user) external view returns (bool);

    function getTotalWallets() external view returns (uint256);

    function userWallets(address user) external view returns (address);

    function walletToUser(address wallet) external view returns (address);

    function totalWallets() external view returns (uint256);
}
