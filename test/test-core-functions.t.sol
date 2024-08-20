// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {UserWallet} from "../src/UserWallet.sol";
import {WalletFactory} from "../src/WalletFactory.sol";
import {PackedUserOperation} from "../lib/account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {IEntryPoint} from "../lib/account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "./mocks/ERCMock.sol";
import {EntryPoint} from "../lib/account-abstraction/contracts/core/EntryPoint.sol";

contract UserWalletTest is Test {
    UserWallet userWallet;
    WalletFactory walletFactory;
    ERC20Mock mockToken;
    EntryPoint entryPoint;
    address owner;
    uint256 ownerPrivateKey;
    address recipient;
    address payable attacker;

    event Received(address sender, uint256 amount);
    event Executed(address target, uint256 value, bytes data);

    function setUp() public {
        console.log("1: Starting setUp function");
        (owner, ownerPrivateKey) = makeAddrAndKey("OWNER");
        console.log("2: Owner address set up:", owner);
        entryPoint = new EntryPoint();
        console.log("3: EntryPoint deployed at:", address(entryPoint));
        recipient = makeAddr("RECIPIENT");
        console.log("4: Recipient address set up:", recipient);
        attacker = payable(makeAddr("ATTACKER"));
        console.log("5: Attacker address set up:", attacker);
        walletFactory = new WalletFactory(address(entryPoint));
        console.log("6: WalletFactory deployed at:", address(walletFactory));
        mockToken = new ERC20Mock("MockToken", "MTK", owner, 1000000);
        console.log("7: MockToken deployed at:", address(mockToken));
        vm.deal(owner, 10 ether);
        console.log("8: Owner funded with 10 ether");
        console.log("9: Owner ETH balance:", owner.balance);
        vm.prank(owner);
        address walletAddress = walletFactory.createWallet();
        userWallet = UserWallet(payable(walletAddress));
        console.log("10: UserWallet created at:", address(userWallet));
        vm.deal(address(userWallet), 1 ether);
        console.log("11: UserWallet funded with 1 ether");
        console.log("12: UserWallet ETH balance:", address(userWallet).balance);
        vm.startPrank(owner);
        mockToken.transfer(address(userWallet), 1000);
        console.log("13: Transferred 1000 tokens to UserWallet");
        vm.stopPrank();
        assertEq(mockToken.balanceOf(address(userWallet)), 1000, "UserWallet should have 1000 tokens");
        console.log("14: UserWallet token balance:", mockToken.balanceOf(address(userWallet)));
        console.log("15: setUp function completed");
    }

    function testExecute() public {
        console.log("16: Starting testExecute function");
        uint256 amount = 100;
        bytes memory transferData = abi.encodeWithSelector(IERC20.transfer.selector, recipient, amount);
        uint256 userWalletBalanceBefore = mockToken.balanceOf(address(userWallet));
        uint256 recipientBalanceBefore = mockToken.balanceOf(recipient);
        console.log("17: UserWallet token balance before transfer:", userWalletBalanceBefore);
        console.log("18: Recipient token balance before transfer:", recipientBalanceBefore);

        vm.prank(owner);
        userWallet.execute(address(mockToken), 0, transferData);

        uint256 userWalletBalanceAfter = mockToken.balanceOf(address(userWallet));
        uint256 recipientBalanceAfter = mockToken.balanceOf(recipient);
        console.log("19: Transfer executed");
        console.log("20: UserWallet token balance after transfer:", userWalletBalanceAfter);
        console.log("21: Recipient token balance after transfer:", recipientBalanceAfter);

        assertEq(recipientBalanceAfter, recipientBalanceBefore + amount, "Recipient should have received the amount");
        assertEq(
            userWalletBalanceAfter,
            userWalletBalanceBefore - amount,
            "UserWallet balance should decrease by amount transferred"
        );
        console.log("22: testExecute function completed");
    }

    function testExecuteViaUserOp() public {
        console.log("23: Starting testExecuteViaUserOp function");
        uint256 amount = 100;
        bytes memory transferData = abi.encodeWithSelector(IERC20.transfer.selector, recipient, amount);
        uint256 userWalletBalanceBefore = mockToken.balanceOf(address(userWallet));
        uint256 recipientBalanceBefore = mockToken.balanceOf(recipient);
        console.log("24: UserWallet token balance before transfer:", userWalletBalanceBefore);
        console.log("25: Recipient token balance before transfer:", recipientBalanceBefore);

        bytes memory callData = abi.encodeWithSelector(UserWallet.execute.selector, address(mockToken), 0, transferData);
        PackedUserOperation memory userOp = PackedUserOperation({
            sender: address(userWallet),
            nonce: 0,
            initCode: "",
            callData: callData,
            accountGasLimits: bytes32(uint256(1000000) << 128 | 1000000),
            preVerificationGas: 100000,
            gasFees: bytes32(uint256(1 gwei) << 128 | 1 gwei),
            paymasterAndData: "",
            signature: ""
        });

        bytes32 userOpHash = entryPoint.getUserOpHash(userOp);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, MessageHashUtils.toEthSignedMessageHash(userOpHash));
        userOp.signature = abi.encodePacked(r, s, v);

        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = userOp;

        console.log("26: Handling UserOperation");
        entryPoint.handleOps(ops, payable(address(this)));

        uint256 userWalletBalanceAfter = mockToken.balanceOf(address(userWallet));
        uint256 recipientBalanceAfter = mockToken.balanceOf(recipient);
        console.log("27: UserWallet token balance after transfer:", userWalletBalanceAfter);
        console.log("28: Recipient token balance after transfer:", recipientBalanceAfter);

        assertEq(
            recipientBalanceAfter,
            recipientBalanceBefore + amount,
            "Recipient should have received the amount via UserOperation"
        );
        assertEq(
            userWalletBalanceAfter,
            userWalletBalanceBefore - amount,
            "UserWallet balance should decrease by amount transferred via UserOperation"
        );
        console.log("29: testExecuteViaUserOp function completed");
    }

    function testValidateUserOp() public {
        console.log("30: Starting testValidateUserOp function");
        bytes memory callData = abi.encodeWithSelector(UserWallet.execute.selector, address(mockToken), 0, "");
        PackedUserOperation memory userOp = PackedUserOperation({
            sender: address(userWallet),
            nonce: 0,
            initCode: "",
            callData: callData,
            accountGasLimits: bytes32(uint256(1000000) << 128 | 1000000),
            preVerificationGas: 100000,
            gasFees: bytes32(uint256(1 gwei) << 128 | 1 gwei),
            paymasterAndData: "",
            signature: ""
        });

        bytes32 userOpHash = entryPoint.getUserOpHash(userOp);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, MessageHashUtils.toEthSignedMessageHash(userOpHash));
        userOp.signature = abi.encodePacked(r, s, v);

        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = userOp;

        uint256 balanceBefore = mockToken.balanceOf(address(userWallet));
        console.log("31: UserWallet token balance before validation:", balanceBefore);

        entryPoint.handleOps(ops, payable(address(this)));

        uint256 balanceAfter = mockToken.balanceOf(address(userWallet));
        console.log("32: UserWallet token balance after validation:", balanceAfter);

        assertEq(balanceAfter, balanceBefore, "Balance should not change for validation");
        console.log("33: testValidateUserOp function completed");
    }

    function testInvalidSignature() public {
        console.log("34: Starting testInvalidSignature function");
        bytes memory callData = abi.encodeWithSelector(UserWallet.execute.selector, address(mockToken), 0, "");
        PackedUserOperation memory userOp = PackedUserOperation({
            sender: address(userWallet),
            nonce: 0,
            initCode: "",
            callData: callData,
            accountGasLimits: bytes32(uint256(1000000) << 128 | 1000000),
            preVerificationGas: 100000,
            gasFees: bytes32(uint256(1 gwei) << 128 | 1 gwei),
            paymasterAndData: "",
            signature: ""
        });

        bytes32 userOpHash = entryPoint.getUserOpHash(userOp);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(uint256(1), MessageHashUtils.toEthSignedMessageHash(userOpHash)); // Using wrong private key
        userOp.signature = abi.encodePacked(r, s, v);

        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = userOp;

        bool reverted = false;
        try entryPoint.handleOps(ops, payable(address(this))) {
            // If this succeeds, the test should fail
        } catch {
            reverted = true;
        }

        assertTrue(reverted, "Handling should have reverted due to invalid signature");
        console.log("35: testInvalidSignature function completed");
    }

    function testWithdraw() public {
        console.log("36: Starting testWithdraw function");
        uint256 initialWalletBalance = address(userWallet).balance;
        uint256 initialOwnerBalance = owner.balance;

        vm.prank(owner);
        userWallet.withdraw();

        uint256 finalWalletBalance = address(userWallet).balance;
        uint256 finalOwnerBalance = owner.balance;

        assertEq(finalWalletBalance, 0, "UserWallet should have 0 balance after withdrawal");
        assertEq(
            finalOwnerBalance,
            initialOwnerBalance + initialWalletBalance,
            "Owner should have received the withdrawn amount"
        );
        console.log("37: testWithdraw function completed");
    }

    function testUnauthorizedWithdraw() public {
        console.log("38: Starting testUnauthorizedWithdraw function");
        vm.prank(attacker);

        bool reverted = false;
        try userWallet.withdraw() {
            // If this succeeds, the test should fail
        } catch {
            reverted = true;
        }

        assertTrue(reverted, "Withdrawal should have reverted for unauthorized user");
        console.log("39: testUnauthorizedWithdraw function completed");
    }

    function testReceiveEther() public {
        console.log("40: Starting testReceiveEther function");
        uint256 initialBalance = address(userWallet).balance;
        uint256 amount = 1 ether;

        (bool success,) = address(userWallet).call{value: amount}("");
        require(success, "Failed to send Ether");

        uint256 finalBalance = address(userWallet).balance;
        assertEq(finalBalance, initialBalance + amount, "UserWallet should have received the Ether");
        console.log("41: testReceiveEther function completed");
    }

    receive() external payable {
        console.log("42: Received payment in contract ooooooooooooooooooooooooooooooooooooooooooooooooooo");
        console.log("43: Contract balance:", address(this).balance);
    }
}
