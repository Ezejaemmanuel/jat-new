// SPDX-License-Identifier:MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {PackedUserOperation} from "../lib/account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {EntryPoint} from "../lib/account-abstraction/contracts/core/EntryPoint.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {IEntryPoint} from "../lib/account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {WalletFactory} from "../src/WalletFactory.sol";
import {DevOpsTools} from "../lib/foundry-devops/src/DevOpsTools.sol";

contract SendUserOperationScript is Script {
    uint256 constant ANVIL_DEFAULT_PRIVATEKEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    function run() public {
        // Setup
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        address usdc = config.usdc;
        uint256 amount = 100 * 10 ** 18; // Example amount

        // Deploy or get the WalletFactory
        WalletFactory walletFactory =
            WalletFactory(DevOpsTools.get_most_recent_deployment("WalletFactory", block.chainid));

        // Create or get the UserWallet for the sender
        address userWalletAddress = walletFactory.getUserWallet(msg.sender);
        address sender = msg.sender;
        if (userWalletAddress == address(0)) {
            vm.prank(sender);
            userWalletAddress = walletFactory.createWallet();
        }

        // Generate the signed user operation
        PackedUserOperation memory userOp = generatedSignedUserOperation(userWalletAddress, usdc, amount, config);
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = userOp;

        // Send transaction
        vm.startBroadcast();
        IEntryPoint(config.entryPoint).handleOps(ops, payable(config.account));
        vm.stopBroadcast();
    }

    function generatedSignedUserOperation(
        address userWalletAddress,
        address usdc,
        uint256 amount,
        HelperConfig.NetworkConfig memory config
    ) public view returns (PackedUserOperation memory) {
        uint256 nonce = vm.getNonce(userWalletAddress) - 1;
        bytes memory callData = abi.encodeWithSelector(IERC20(usdc).transfer.selector, userWalletAddress, amount);
        PackedUserOperation memory unsignedUserOp = _generateUnsignedUserOperation(userWalletAddress, nonce, callData);
        bytes32 userOpHash = IEntryPoint(config.entryPoint).getUserOpHash(unsignedUserOp);
        bytes32 messageHash = MessageHashUtils.toEthSignedMessageHash(userOpHash);
        uint8 v;
        bytes32 r;
        bytes32 s;
        if (block.chainid == 31337) {
            (v, r, s) = vm.sign(ANVIL_DEFAULT_PRIVATEKEY, messageHash);
        } else {
            (v, r, s) = vm.sign(config.account, messageHash);
        }
        bytes memory signature = abi.encodePacked(r, s, v);
        PackedUserOperation memory signedUserOp = unsignedUserOp;
        signedUserOp.signature = signature;
        return signedUserOp;
    }

    function _generateUnsignedUserOperation(address sender, uint256 nonce, bytes memory callData)
        internal
        pure
        returns (PackedUserOperation memory)
    {
        uint128 verificationGasLimit = 16777216;
        uint128 callGasLimit = verificationGasLimit;
        uint128 maxPriorityFeePerGas = 256;
        uint128 maxFeePerGas = maxPriorityFeePerGas;
        return PackedUserOperation({
            sender: sender,
            nonce: nonce,
            initCode: hex"",
            callData: callData,
            accountGasLimits: bytes32(uint256(verificationGasLimit) << 128 | callGasLimit),
            preVerificationGas: verificationGasLimit,
            gasFees: bytes32(uint256(maxPriorityFeePerGas) << 128 | maxFeePerGas),
            paymasterAndData: hex"",
            signature: hex""
        });
    }
}
