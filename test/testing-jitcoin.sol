// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {JITCoin} from "../src/JitCoin.sol";
import {WalletFactory} from "../src/WalletFactory.sol";
import {UserWallet} from "../src/UserWallet.sol";

import {
    IOAppOptionsType3,
    EnforcedOptionParam
} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OAppOptionsType3.sol";
import {OptionsBuilder} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";

import {IOFT, SendParam, OFTReceipt} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";
import {
    MessagingFee,
    MessagingReceipt
} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {OFTMsgCodec} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/libs/OFTMsgCodec.sol";
import {OFTComposeMsgCodec} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/libs/OFTComposeMsgCodec.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "forge-std/console.sol";

import {TestHelperOz5} from "./Helpers/TestHelperOz5.sol";

contract JITCoinTest is TestHelperOz5 {
    using OptionsBuilder for bytes;

    uint32 private aEid = 1;
    uint32 private bEid = 2;

    JITCoin private aJITCoin;
    JITCoin private bJITCoin;

    WalletFactory private walletFactory;
    UserWallet private userWalletA;
    UserWallet private userWalletB;

    address private userA = address(0x1);
    address private userB = address(0x2);
    uint256 private initialBalance = 100 ether;

    function setUp() public virtual override {
        vm.deal(userA, 1000 ether);
        vm.deal(userB, 1000 ether);

        super.setUp();
        setUpEndpoints(2, LibraryType.UltraLightNode);

        // Deploy WalletFactory
        walletFactory = new WalletFactory(address(endpoints[aEid]));

        // Deploy JITCoin contracts
        aJITCoin = JITCoin(
            _deployOApp(
                type(JITCoin).creationCode,
                abi.encode("JITCoin A", "JITA", address(endpoints[aEid]), address(this), address(walletFactory))
            )
        );

        bJITCoin = JITCoin(
            _deployOApp(
                type(JITCoin).creationCode,
                abi.encode("JITCoin B", "JITB", address(endpoints[bEid]), address(this), address(walletFactory))
            )
        );

        // Config and wire the JITCoins
        address[] memory JITCoins = new address[](2);
        JITCoins[0] = address(aJITCoin);
        JITCoins[1] = address(bJITCoin);
        this.wireOApps(JITCoins);

        // Create user wallets
        vm.prank(userA);
        userWalletA = UserWallet(payable(walletFactory.createWallet()));
        vm.prank(userB);
        userWalletB = UserWallet(payable(walletFactory.createWallet()));

        // Mint initial JITCoins
        vm.deal(address(userWalletA), initialBalance);
        vm.prank(address(userWalletA));
        aJITCoin.mint{value: initialBalance}();

        vm.deal(address(userWalletB), initialBalance);
        vm.prank(address(userWalletB));
        bJITCoin.mint{value: initialBalance}();
    }

    function test_constructor() public {
        assertEq(aJITCoin.owner(), address(this));
        assertEq(bJITCoin.owner(), address(this));

        assertEq(aJITCoin.balanceOf(address(userWalletA)), initialBalance);
        assertEq(bJITCoin.balanceOf(address(userWalletB)), initialBalance);

        assertEq(aJITCoin.walletFactory(), address(walletFactory));
        assertEq(bJITCoin.walletFactory(), address(walletFactory));
    }

    function test_send_JITCoin() public {
        uint256 tokensToSend = 1 ether;
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam =
            SendParam(bEid, addressToBytes32(address(userWalletB)), tokensToSend, tokensToSend, options, "", "");
        MessagingFee memory fee = aJITCoin.quoteSend(sendParam, false);

        assertEq(aJITCoin.balanceOf(address(userWalletA)), initialBalance);
        assertEq(bJITCoin.balanceOf(address(userWalletB)), initialBalance);

        vm.prank(address(userWalletA));
        aJITCoin.send{value: fee.nativeFee}(sendParam, fee, payable(address(this)));
        verifyPackets(bEid, addressToBytes32(address(bJITCoin)));

        assertEq(aJITCoin.balanceOf(address(userWalletA)), initialBalance - tokensToSend);
        assertEq(bJITCoin.balanceOf(address(userWalletB)), initialBalance + tokensToSend);
    }

    // Add more tests as needed, similar to the MyOFTTest
}
