// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {UserWallet} from "../src/UserWallet.sol";
import {WalletFactory} from "../src/WalletFactory.sol";
import {ERC20Mock} from "./mocks/ERCMock.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {DeployScript} from "../script/DeployScript.s.sol";
import {IEntryPoint} from "../lib/account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "../lib/account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

contract UserWalletTest is Test {
    using MessageHashUtils for bytes32;

    UserWallet userWallet;
    WalletFactory walletFactory;
    HelperConfig helperConfig;
    ERC20Mock usdc;
    IEntryPoint entryPoint;
    address owner = makeAddr("owner");
    address randomUser = makeAddr("randomUser");
    uint256 constant INITIAL_BALANCE = 1 ether;
    uint256 constant TRANSFER_AMOUNT = 0.5 ether;
    uint256 constant AMOUNT = 1e18;

    function setUp() public {
        console.log("setUp: Initializing test environment");

        // Deploy the DeployScript and run it
        DeployScript deployScript = new DeployScript();
        (walletFactory, helperConfig) = deployScript.run();

        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        entryPoint = IEntryPoint(config.entryPoint);

        console.log("setUp: EntryPoint set to", address(entryPoint));
        console.log("setUp: WalletFactory deployed");

        // Create a UserWallet
        vm.prank(owner);
        address walletAddress = walletFactory.createWallet();
        userWallet = UserWallet(payable(walletAddress));

        console.log("setUp: UserWallet created at", walletAddress);

        // Deploy the USDC mock token directly within the test
        usdc = new ERC20Mock("Mock USDC", "USDC", owner, 1000 * 10 ** 18);

        console.log("setUp: Mock USDC token deployed at", address(usdc));

        // Initialize the SendUserOperationScript

        // Fund the UserWallet
        vm.deal(address(userWallet), INITIAL_BALANCE);

        console.log("setUp: UserWallet funded with", INITIAL_BALANCE);
    }

    function testWalletInitialization() public {
        console.log("testWalletInitialization: Starting test");
        assertEq(userWallet.owner(), owner);
        console.log("testWalletInitialization: Owner verified");
        assertEq(address(userWallet.getEntryPoint()), address(entryPoint));
        console.log("testWalletInitialization: EntryPoint verified");
    }

    function testOwnerCanExecute() public {
        console.log("testOwnerCanExecute: Starting test");
        uint256 amount = 100;
        bytes memory data = abi.encodeWithSelector(ERC20Mock.mint.selector, address(userWallet), amount);
        console.log("testOwnerCanExecute: Prepared mint data");
        vm.prank(owner);
        userWallet.execute(address(usdc), 0, data);
        console.log("testOwnerCanExecute: Executed mint operation");
        assertEq(usdc.balanceOf(address(userWallet)), amount);
        console.log("testOwnerCanExecute: Balance verified");
    }

    function testNonOwnerCannotExecute() public {
        console.log("testNonOwnerCannotExecute: Starting test");
        bytes memory data = abi.encodeWithSelector(ERC20Mock.mint.selector, address(userWallet), 100);
        vm.prank(randomUser);
        vm.expectRevert(UserWallet.UserWallet__NotFromEntryPointOrOwner.selector);
        userWallet.execute(address(usdc), 0, data);
        console.log("testNonOwnerCannotExecute: Execution reverted as expected");
    }

    function testReceiveEther() public {
        console.log("testReceiveEther: Starting test");
        uint256 initialBalance = address(userWallet).balance;
        console.log("testReceiveEther: Initial balance", initialBalance);
        (bool success,) = address(userWallet).call{value: 1 ether}("");
        require(success, "Transfer failed");
        console.log("testReceiveEther: Ether transferred");
        assertEq(address(userWallet).balance, initialBalance + 1 ether);
        console.log("testReceiveEther: New balance verified");
    }

    function testWithdraw() public {
        console.log("testWithdraw: Starting test");
        uint256 initialBalance = owner.balance;
        console.log("testWithdraw: Initial owner balance", initialBalance);
        vm.prank(owner);
        userWallet.withdraw();
        console.log("testWithdraw: Withdrawal executed");
        assertEq(address(userWallet).balance, 0);
        console.log("testWithdraw: UserWallet balance verified");
        assertEq(owner.balance, initialBalance + INITIAL_BALANCE);
        console.log("testWithdraw: Owner balance verified");
    }

    function testFailWithdrawAsNonOwner() public {
        console.log("testFailWithdrawAsNonOwner: Starting test");
        vm.prank(randomUser);
        vm.expectRevert("Ownable: caller is not the owner");
        userWallet.withdraw();
        console.log("testFailWithdrawAsNonOwner: Withdrawal reverted as expected");
    }

    function testGetBalance() public {
        console.log("testGetBalance: Starting test");
        assertEq(userWallet.getBalance(), INITIAL_BALANCE);
        console.log("testGetBalance: Balance verified");
    }
}
