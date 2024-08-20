// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {EntryPoint} from "../lib/account-abstraction/contracts/core/EntryPoint.sol";
import {WalletFactory} from "../src/WalletFactory.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployScript is Script {
    function run() public returns (WalletFactory, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        vm.startBroadcast(config.account);
        WalletFactory walletFactory = new WalletFactory(config.entryPoint);
        vm.stopBroadcast();

        return (walletFactory, helperConfig);
    }
}
