// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {WrappedENS} from "../../src/bridges/WrappedENS.sol";
import {Adapter8004} from "../../src/Adapter8004.sol";
import {IERCAgentBindings} from "../../src/interfaces/IERCAgentBindings.sol";
import {MockIdentityRegistry} from "../mocks/MockIdentityRegistry.sol";

contract WrappedENSTest is Test {
    WrappedENS internal wrapped;
    Adapter8004 internal adapter;
    MockIdentityRegistry internal registry;

    address internal admin = makeAddr("admin");
    address internal relayer = makeAddr("relayer");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    // ENS labels are WITHOUT the .eth suffix
    string internal constant ALICE_LABEL = "alice";
    string internal constant BOB_LABEL = "bob";

    function setUp() external {
        wrapped = new WrappedENS(admin, relayer);

        registry = new MockIdentityRegistry();
        Adapter8004 impl = new Adapter8004();
        ERC1967Proxy proxy =
            new ERC1967Proxy(address(impl), abi.encodeCall(Adapter8004.initialize, (address(registry), admin)));
        adapter = Adapter8004(address(proxy));
    }

    // -------------------------------------------------------------------------
    // syncOwnership
    // -------------------------------------------------------------------------

    function testSyncOwnershipMints() external {
        vm.prank(relayer);
        wrapped.syncOwnership(ALICE_LABEL, alice);

        uint256 tokenId = wrapped.labelToTokenId(ALICE_LABEL);
        assertEq(wrapped.ownerOf(tokenId), alice);
        assertEq(wrapped.labelOf(tokenId), ALICE_LABEL);
    }

    function testSyncOwnershipTransfersOwner() external {
        vm.prank(relayer);
        wrapped.syncOwnership(ALICE_LABEL, alice);
        vm.prank(relayer);
        wrapped.syncOwnership(ALICE_LABEL, bob);

        assertEq(wrapped.ownerOf(wrapped.labelToTokenId(ALICE_LABEL)), bob);
    }

    function testSyncOwnershipRevertsForNonRelayer() external {
        vm.prank(alice);
        vm.expectRevert(WrappedENS.OnlyRelayer.selector);
        wrapped.syncOwnership(ALICE_LABEL, alice);
    }

    // -------------------------------------------------------------------------
    // burn
    // -------------------------------------------------------------------------

    function testBurnRemovesToken() external {
        vm.prank(relayer);
        wrapped.syncOwnership(ALICE_LABEL, alice);
        vm.prank(relayer);
        wrapped.burn(ALICE_LABEL);

        uint256 tokenId = wrapped.labelToTokenId(ALICE_LABEL);
        vm.expectRevert();
        wrapped.ownerOf(tokenId);
    }

    function testBurnRevertsIfNotMinted() external {
        vm.prank(relayer);
        vm.expectRevert(abi.encodeWithSelector(WrappedENS.LabelNotMinted.selector, ALICE_LABEL));
        wrapped.burn(ALICE_LABEL);
    }

    // -------------------------------------------------------------------------
    // EVM transfer blocking
    // -------------------------------------------------------------------------

    function testTransferFromReverts() external {
        vm.prank(relayer);
        wrapped.syncOwnership(ALICE_LABEL, alice);
        uint256 tokenId = wrapped.labelToTokenId(ALICE_LABEL);

        vm.prank(alice);
        vm.expectRevert(WrappedENS.EVMTransfersBlocked.selector);
        wrapped.transferFrom(alice, bob, tokenId);
    }

    function testApproveReverts() external {
        vm.prank(relayer);
        wrapped.syncOwnership(ALICE_LABEL, alice);
        uint256 tokenId = wrapped.labelToTokenId(ALICE_LABEL);

        vm.prank(alice);
        vm.expectRevert(WrappedENS.EVMTransfersBlocked.selector);
        wrapped.approve(bob, tokenId);
    }

    function testSetApprovalForAllReverts() external {
        vm.prank(alice);
        vm.expectRevert(WrappedENS.EVMTransfersBlocked.selector);
        wrapped.setApprovalForAll(bob, true);
    }

    // -------------------------------------------------------------------------
    // labelToTokenId
    // -------------------------------------------------------------------------

    function testLabelToTokenIdMatchesENSBaseRegistrarConvention() external view {
        // ENS BaseRegistrar tokenId = uint256(keccak256(label))
        uint256 expected = uint256(keccak256(abi.encodePacked(ALICE_LABEL)));
        assertEq(wrapped.labelToTokenId(ALICE_LABEL), expected);
    }

    function testDifferentLabelsProduceDifferentTokenIds() external view {
        assertNotEq(wrapped.labelToTokenId(ALICE_LABEL), wrapped.labelToTokenId(BOB_LABEL));
    }

    // -------------------------------------------------------------------------
    // Adapter integration — end-to-end
    // -------------------------------------------------------------------------

    function testAdapterControlFollowsENSOwnershipAcrossSync() external {
        // 1. Relayer mirrors alice.eth ownership from mainnet.
        vm.prank(relayer);
        wrapped.syncOwnership(ALICE_LABEL, alice);

        uint256 tokenId = wrapped.labelToTokenId(ALICE_LABEL);

        // 2. Alice registers an ERC-8004 agent bound to alice.eth.
        vm.prank(alice);
        uint256 agentId =
            adapter.register(IERCAgentBindings.TokenStandard.ERC721, address(wrapped), tokenId, "ipfs://alice-ens");

        assertTrue(adapter.isController(agentId, alice));

        // 3. alice.eth is transferred on mainnet. Relayer syncs.
        vm.prank(relayer);
        wrapped.syncOwnership(ALICE_LABEL, bob);

        assertFalse(adapter.isController(agentId, alice));
        assertTrue(adapter.isController(agentId, bob));
    }

    function testAdapterControlDropsWhenNameExpires() external {
        vm.prank(relayer);
        wrapped.syncOwnership(ALICE_LABEL, alice);
        uint256 tokenId = wrapped.labelToTokenId(ALICE_LABEL);

        vm.prank(alice);
        uint256 agentId =
            adapter.register(IERCAgentBindings.TokenStandard.ERC721, address(wrapped), tokenId, "ipfs://alice-ens");

        assertTrue(adapter.isController(agentId, alice));

        // ENS name expires; relayer burns the wrapped token.
        vm.prank(relayer);
        wrapped.burn(ALICE_LABEL);

        // After burn, ownerOf reverts on the wrapped token, so any controller-gated
        // adapter operation also reverts. No account can drive the agent.
        vm.prank(alice);
        vm.expectRevert();
        adapter.setAgentURI(agentId, "ipfs://hijack");

        vm.prank(bob);
        vm.expectRevert();
        adapter.setAgentURI(agentId, "ipfs://hijack");
    }

    function testSetRelayerIsOwnerOnly() external {
        vm.prank(alice);
        vm.expectRevert();
        wrapped.setRelayer(alice);

        vm.prank(admin);
        wrapped.setRelayer(alice);
        assertEq(wrapped.relayer(), alice);
    }
}
