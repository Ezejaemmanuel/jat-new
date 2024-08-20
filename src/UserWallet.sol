// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAccount} from "../lib/account-abstraction/contracts/interfaces/IAccount.sol";
import {PackedUserOperation} from "../lib/account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {SIG_VALIDATION_FAILED, SIG_VALIDATION_SUCCESS} from "../lib/account-abstraction/contracts/core/Helpers.sol";
import {IEntryPoint} from "../lib/account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {console} from "forge-std/console.sol";

contract UserWallet is IAccount, Ownable {
    error UserWallet__PrefundFailed();
    error UserWallet__NotFromEntryPoint();
    error UserWallet__NotFromEntryPointOrOwner();
    error UserWallet__ExecuteFailed(bytes);
    error UserWallet__WidthdrawalFailed();

    event Received(address sender, uint256 amount);
    event Executed(address target, uint256 value, bytes data);

    IEntryPoint private immutable i_entryPoint;

    modifier RequireFromEntryPoint() {
        console.log("RequireFromEntryPoint: Checking if sender is EntryPoint");
        if (msg.sender != address(i_entryPoint)) {
            console.log("RequireFromEntryPoint: Sender is not EntryPoint");
            revert UserWallet__NotFromEntryPoint();
        }
        _;
    }

    modifier RequireFromEntryPointOrOwner() {
        console.log("RequireFromEntryPointOrOwner: Checking sender");
        if (msg.sender != address(i_entryPoint) && msg.sender != owner()) {
            console.log("RequireFromEntryPointOrOwner: Sender is neither EntryPoint nor owner");
            revert UserWallet__NotFromEntryPointOrOwner();
        }
        _;
    }

    constructor(address _ownerAddress, address _entryPointAddress) Ownable(_ownerAddress) {
        console.log("Constructor: Deploying UserWallet with owner:", _ownerAddress);
        i_entryPoint = IEntryPoint(_entryPointAddress);
        console.log("Constructor: EntryPoint set to:", _entryPointAddress);
    }

    function validateUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash, uint256 missingAccountFunds)
        external
        RequireFromEntryPoint
        returns (uint256 validationData)
    {
        console.log("validateUserOp: Validating user operation");
        validationData = _validateSignature(userOp, userOpHash);
        console.log("validateUserOp: Signature validation result:", validationData);
        _payPrefund(missingAccountFunds);
        console.log("validateUserOp: Prefund paid");
        return validationData;
    }

    function _payPrefund(uint256 _missingAccountFunds) internal {
        console.log("_payPrefund: Missing account funds:", _missingAccountFunds);
        if (_missingAccountFunds != 0) {
            console.log("_payPrefund: Attempting to pay prefund");
            (bool success,) = payable(msg.sender).call{value: _missingAccountFunds, gas: type(uint96).max}("");
            if (!success) {
                console.log("_payPrefund: Prefund payment failed");
                revert UserWallet__PrefundFailed();
            }
            console.log("_payPrefund: Prefund payment successful");
        }
    }

    function _validateSignature(PackedUserOperation calldata userOp, bytes32 userOpHash)
        internal
        view
        returns (uint256 validationData)
    {
        console.log("_validateSignature: Validating signature");
        bytes32 messageHash = MessageHashUtils.toEthSignedMessageHash(userOpHash);
        address recoveredAddress = ECDSA.recover(messageHash, userOp.signature);
        console.log("_validateSignature: Recovered address:", recoveredAddress);

        if (recoveredAddress == owner()) {
            console.log("_validateSignature: Signature valid");
            return SIG_VALIDATION_SUCCESS;
        } else {
            console.log("_validateSignature: Signature invalid");
            return SIG_VALIDATION_FAILED;
        }
    }

    function execute(address destination, uint256 value, bytes calldata functionData)
        external
        RequireFromEntryPointOrOwner
    {
        console.log("execute: Executing transaction to:", destination);
        console.log("execute: Transaction value:", value);
        (bool success, bytes memory result) = destination.call{value: value}(functionData);
        if (!success) {
            console.log("execute: Transaction failed");
            revert UserWallet__ExecuteFailed(result);
        }
        console.log("execute: Transaction successful");
        emit Executed(destination, value, functionData);
    }

    receive() external payable {
        console.log("receive: Received Ether from:", msg.sender);
        console.log("receive: Amount received:", msg.value);
        emit Received(msg.sender, msg.value);
    }

    function getBalance() external view returns (uint256) {
        uint256 balance = address(this).balance;
        console.log("getBalance: Current balance:", balance);
        return balance;
    }

    function withdraw() external onlyOwner {
        uint256 amount = address(this).balance;
        console.log("withdraw: Attempting to withdraw:", amount);
        (bool success,) = payable(msg.sender).call{value: amount}("");
        if (!success) {
            revert UserWallet__WidthdrawalFailed();
        }
        console.log("withdraw: Withdrawal successful");
    }
    // In UserWallet.sol

    function isUserWallet() public pure returns (bool) {
        return true;
    }

    function getEntryPoint() external view returns (address) {
        console.log("getEntryPoint: Returning EntryPoint address");
        return address(i_entryPoint);
    }
}
