// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {Script, console} from "forge-std/Script.sol";
import {Vm} from "forge-std/Vm.sol";
import {Dapper} from "../src/Dapper.sol";
import {Vault} from "../src/Vault.sol";

contract DeployScript is Script {
    Dapper public musdDapper;
    Dapper public btcDapper;
    Vault public musdYieldVault;
    Vault public btcYieldVault;
    address public musdBeneficiaryVault;
    address public btcBeneficiaryVault;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        bool isUsingMezoNetwork = false;

        address musd = isUsingMezoNetwork ? 0x118917a40FAF1CD7a13dB0Ef56C86De7973Ac503 : 0xdf6734d11ee027cCC4d7f32ecE5162b0c4018aB0;
        address btc = isUsingMezoNetwork ? 0x7b7C000000000000000000000000000000000000 : 0x1699A1838f24b1b5D55BB1098E38F82F7C8D8570;

        musdYieldVault = new Vault(musd, "MUSD Yield Vault Token", "musdYIELD"); // Simulated for testnet -> otherwise would be the existing vault
        btcYieldVault = new Vault(btc, "BTC Yield Vault Token", "btcYIELD"); // Simulated for testnet -> otherwise would be the existing vault

        uint256 annualInterestRateBpsMusd = 1200; // 12%
        uint256 annualInterestRateBpsBtc = 1000; // 10%
        
        musdDapper = new Dapper(musd, annualInterestRateBpsMusd, address(musdYieldVault));
        btcDapper = new Dapper(btc, annualInterestRateBpsBtc, address(btcYieldVault));

        musdBeneficiaryVault = musdDapper.getBeneficiaryVaultAddress();
        btcBeneficiaryVault = btcDapper.getBeneficiaryVaultAddress();
        
        console.log("NEXT_DEPLOY_BLOCK=", block.number);
        console.log("NEXT_DEPLOY_TIMESTAMP=", block.timestamp);
        console.log("NEXT_PUBLIC_MUSD_DAPPER=", address(musdDapper));
        console.log("NEXT_PUBLIC_BTC_DAPPER=", address(btcDapper));
        console.log("NEXT_PUBLIC_MUSD_YIELD_VAULT=", address(musdYieldVault));
        console.log("NEXT_PUBLIC_BTC_YIELD_VAULT=", address(btcYieldVault));
        console.log("NEXT_PUBLIC_MUSD_BENEFICIARY_VAULT=", musdBeneficiaryVault);
        console.log("NEXT_PUBLIC_BTC_BENEFICIARY_VAULT=", btcBeneficiaryVault);
        vm.stopBroadcast();
    }
}
