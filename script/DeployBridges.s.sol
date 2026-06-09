// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {WrappedBNSv2} from "../src/bridges/WrappedBNSv2.sol";
import {WrappedENS} from "../src/bridges/WrappedENS.sol";

/// @notice Deploys WrappedBNSv2 and WrappedENS bridge contracts.
///
/// Required environment variables:
///   DEPLOYER_PRIVATE_KEY  — deployer EOA; becomes the contract owner (can rotate relayer)
///   BRIDGE_RELAYER        — address authorised to call syncOwnership and burn
///
/// Optional (omit to skip that contract):
///   DEPLOY_BNS_BRIDGE=true
///   DEPLOY_ENS_BRIDGE=true
///
/// Usage:
///   forge script script/DeployBridges.s.sol --rpc-url $RPC_URL --broadcast
///   forge script script/DeployBridges.s.sol --rpc-url $BASE_RPC_URL --broadcast
contract DeployBridgesScript is Script {
    function run() external returns (address bnsv2, address ens) {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        address relayer = vm.envAddress("BRIDGE_RELAYER");

        bool deployBNS = _envBoolOr("DEPLOY_BNS_BRIDGE", true);
        bool deployENS = _envBoolOr("DEPLOY_ENS_BRIDGE", true);

        vm.startBroadcast(deployerKey);

        if (deployBNS) {
            WrappedBNSv2 wrapped = new WrappedBNSv2(deployer, relayer);
            bnsv2 = address(wrapped);
            console2.log("WrappedBNSv2 deployed at:", bnsv2);
        }

        if (deployENS) {
            WrappedENS wrapped = new WrappedENS(deployer, relayer);
            ens = address(wrapped);
            console2.log("WrappedENS deployed at:  ", ens);
        }

        vm.stopBroadcast();

        console2.log("Owner (rotate relayer via setRelayer):", deployer);
        console2.log("Relayer (syncOwnership / burn):       ", relayer);
        console2.log("");
        console2.log("Next: call adapter.register(TokenStandard.ERC721, <bridge>, tokenId, agentURI)");
    }

    function _envBoolOr(string memory key, bool defaultVal) internal view returns (bool) {
        try vm.envBool(key) returns (bool v) {
            return v;
        } catch {
            return defaultVal;
        }
    }
}
