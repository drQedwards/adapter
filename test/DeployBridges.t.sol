// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DeployBridgesScript} from "../script/DeployBridges.s.sol";

/// @dev The script is driven by process-global env vars (DEPLOY_BNS_BRIDGE / DEPLOY_ENS_BRIDGE).
/// Foundry executes test functions in parallel and `vm.setEnv` mutates shared process state, so
/// splitting these flag permutations across separate test functions races. All scenarios are
/// therefore exercised sequentially inside a single function, where env reads/writes are stable.
contract DeployBridgesScriptTest is Test {
    // Anvil default key #0 / its address — a valid key so vm.startBroadcast succeeds in-test.
    string internal constant KEY = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";
    address internal constant RELAYER = 0xd83113dCf145bF72F640DbD2141dCB9B14A53789;

    function _baseEnv() internal {
        vm.setEnv("DEPLOYER_PRIVATE_KEY", KEY);
        vm.setEnv("BRIDGE_RELAYER", vm.toString(RELAYER));
        vm.setEnv("DEPLOY_BNS_BRIDGE", "true");
        vm.setEnv("DEPLOY_ENS_BRIDGE", "true");
    }

    function testFlagAndMainnetGuardBehavior() external {
        DeployBridgesScript script = new DeployBridgesScript();

        // 1. Off mainnet, both flags default true -> both deploy.
        _baseEnv();
        vm.chainId(8453); // Base
        (address bnsv2, address ens) = script.run();
        assertTrue(bnsv2 != address(0), "BNS should deploy off mainnet");
        assertTrue(ens != address(0), "ENS should deploy off mainnet");

        // 2. Mainnet with ENS left enabled -> hard revert (no WrappedENS on mainnet).
        _baseEnv();
        vm.chainId(1);
        vm.expectRevert(DeployBridgesScript.WrappedENSNotAllowedOnMainnet.selector);
        script.run();

        // 3. Mainnet with ENS explicitly disabled -> BNS only.
        _baseEnv();
        vm.setEnv("DEPLOY_ENS_BRIDGE", "false");
        vm.chainId(1);
        (bnsv2, ens) = script.run();
        assertTrue(bnsv2 != address(0), "BNS should deploy on mainnet");
        assertEq(ens, address(0), "ENS must not deploy on mainnet");

        // 4. Off mainnet, BNS disabled -> ENS only.
        _baseEnv();
        vm.setEnv("DEPLOY_BNS_BRIDGE", "false");
        vm.chainId(8453);
        (bnsv2, ens) = script.run();
        assertEq(bnsv2, address(0), "BNS skipped");
        assertTrue(ens != address(0), "ENS deployed off mainnet");
    }
}
