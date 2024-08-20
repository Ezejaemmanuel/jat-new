// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAccount} from "../../lib/account-abstraction/contracts/interfaces/IAccount.sol";
import {PackedUserOperation} from "../../lib/account-abstraction/contracts/interfaces/PackedUserOperation.sol";

interface IUserWallet is IAccount {
    event Received(address sender, uint256 amount);
    event Executed(address target, uint256 value, bytes data);

    function validateUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash, uint256 missingAccountFunds)
        external
        returns (uint256 validationData);

    function execute(address destination, uint256 value, bytes calldata functionData) external;

    function getBalance() external view returns (uint256);

    function withdraw() external;

    function isUserWallet() external pure returns (bool);

    function getEntryPoint() external view returns (address);

    // Inherited from Ownable, but included for completeness
    function owner() external view returns (address);
    function transferOwnership(address newOwner) external;
    function renounceOwnership() external;
}
