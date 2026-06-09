// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {WrappedBNSv2} from "../../src/bridges/WrappedBNSv2.sol";
import {Adapter8004} from "../../src/Adapter8004.sol";
import {IERCAgentBindings} from "../../src/interfaces/IERCAgentBindings.sol";
import {MockIdentityRegistry} from "../mocks/MockIdentityRegistry.sol";

contract WrappedBNSv2Test is Test {
    WrappedBNSv2 internal wrapped;
    Adapter8004 internal adapter;
    MockIdentityRegistry internal registry;

    address internal admin = makeAddr("admin");
    address internal relayer = makeAddr("relayer");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    string internal constant ALICE_NAME = "alice.btc";
    string internal constant BOB_NAME = "bob.btc";

    function setUp() external {
        wrapped = new WrappedBNSv2(admin, relayer);

        registry = new MockIdentityRegistry();
        Adapter8004 impl = new Adapter8004();
        ERC1967Proxy proxy =
            new ERC1967Proxy(address(impl), abi.encodeCall(Adapter8004.initialize, (address(registry), admin)));
        adapter = Adapter8004(address(proxy));
    }

    // -------------------------------------------------------------------------
    // syncOwnership
    // -------------------------------------------------------------------------

    function testSyncOwnershipMintsOnFirstSync() external {
        vm.prank(relayer);
        wrapped.syncOwnership(ALICE_NAME, alice);

        uint256 tokenId = wrapped.nameToTokenId(ALICE_NAME);
        assertEq(wrapped.ownerOf(tokenId), alice);
        assertEq(wrapped.nameOf(tokenId), ALICE_NAME);
    }

    function testSyncOwnershipTransfersOnSubsequentSync() external {
        vm.prank(relayer);
        wrapped.syncOwnership(ALICE_NAME, alice);
        vm.prank(relayer);
        wrapped.syncOwnership(ALICE_NAME, bob);

        assertEq(wrapped.ownerOf(wrapped.nameToTokenId(ALICE_NAME)), bob);
    }

    function testSyncOwnershipIsNoopIfOwnerUnchanged() external {
        vm.prank(relayer);
        wrapped.syncOwnership(ALICE_NAME, alice);

        // Calling again with the same owner should not revert
        vm.prank(relayer);
        wrapped.syncOwnership(ALICE_NAME, alice);

        assertEq(wrapped.ownerOf(wrapped.nameToTokenId(ALICE_NAME)), alice);
    }

    function testSyncOwnershipRevertsForNonRelayer() external {
        vm.prank(alice);
        vm.expectRevert(WrappedBNSv2.OnlyRelayer.selector);
        wrapped.syncOwnership(ALICE_NAME, alice);
    }

    function testSyncOwnershipEmitsEvent() external {
        uint256 tokenId = wrapped.nameToTokenId(ALICE_NAME);
        vm.expectEmit(true, true, false, true);
        emit WrappedBNSv2.OwnershipSynced(tokenId, ALICE_NAME, alice);
        vm.prank(relayer);
        wrapped.syncOwnership(ALICE_NAME, alice);
    }

    // -------------------------------------------------------------------------
    // burn
    // -------------------------------------------------------------------------

    function testBurnRemovesToken() external {
        vm.prank(relayer);
        wrapped.syncOwnership(ALICE_NAME, alice);
        vm.prank(relayer);
        wrapped.burn(ALICE_NAME);

        uint256 tokenId = wrapped.nameToTokenId(ALICE_NAME);
        vm.expectRevert();
        wrapped.ownerOf(tokenId);
    }

    function testBurnPreservesNameMapping() external {
        vm.prank(relayer);
        wrapped.syncOwnership(ALICE_NAME, alice);
        uint256 tokenId = wrapped.nameToTokenId(ALICE_NAME);
        vm.prank(relayer);
        wrapped.burn(ALICE_NAME);

        // Name mapping persists for re-mint
        assertEq(wrapped.nameOf(tokenId), ALICE_NAME);
    }

    function testBurnRevertsIfNotMinted() external {
        vm.prank(relayer);
        vm.expectRevert(abi.encodeWithSelector(WrappedBNSv2.NameNotMinted.selector, ALICE_NAME));
        wrapped.burn(ALICE_NAME);
    }

    function testBurnRevertsForNonRelayer() external {
        vm.prank(relayer);
        wrapped.syncOwnership(ALICE_NAME, alice);

        vm.prank(alice);
        vm.expectRevert(WrappedBNSv2.OnlyRelayer.selector);
        wrapped.burn(ALICE_NAME);
    }

    function testBurnThenReMint() external {
        vm.prank(relayer);
        wrapped.syncOwnership(ALICE_NAME, alice);
        vm.prank(relayer);
        wrapped.burn(ALICE_NAME);

        // Re-mint to bob after expiry
        vm.prank(relayer);
        wrapped.syncOwnership(ALICE_NAME, bob);
        assertEq(wrapped.ownerOf(wrapped.nameToTokenId(ALICE_NAME)), bob);
    }

    // -------------------------------------------------------------------------
    // EVM transfer blocking
    // -------------------------------------------------------------------------

    function testTransferFromRevertsWithEVMTransfersBlocked() external {
        vm.prank(relayer);
        wrapped.syncOwnership(ALICE_NAME, alice);
        uint256 tokenId = wrapped.nameToTokenId(ALICE_NAME);

        vm.prank(alice);
        vm.expectRevert(WrappedBNSv2.EVMTransfersBlocked.selector);
        wrapped.transferFrom(alice, bob, tokenId);
    }

    function testSafeTransferFromRevertsWithEVMTransfersBlocked() external {
        vm.prank(relayer);
        wrapped.syncOwnership(ALICE_NAME, alice);
        uint256 tokenId = wrapped.nameToTokenId(ALICE_NAME);

        vm.prank(alice);
        vm.expectRevert(WrappedBNSv2.EVMTransfersBlocked.selector);
        wrapped.safeTransferFrom(alice, bob, tokenId);
    }

    function testApproveRevertsWithEVMTransfersBlocked() external {
        vm.prank(relayer);
        wrapped.syncOwnership(ALICE_NAME, alice);
        uint256 tokenId = wrapped.nameToTokenId(ALICE_NAME);

        vm.prank(alice);
        vm.expectRevert(WrappedBNSv2.EVMTransfersBlocked.selector);
        wrapped.approve(bob, tokenId);
    }

    function testSetApprovalForAllRevertsWithEVMTransfersBlocked() external {
        vm.prank(alice);
        vm.expectRevert(WrappedBNSv2.EVMTransfersBlocked.selector);
        wrapped.setApprovalForAll(bob, true);
    }

    // -------------------------------------------------------------------------
    // setRelayer
    // -------------------------------------------------------------------------

    function testSetRelayerIsOwnerOnly() external {
        vm.prank(alice);
        vm.expectRevert();
        wrapped.setRelayer(alice);

        vm.prank(admin);
        wrapped.setRelayer(alice);
        assertEq(wrapped.relayer(), alice);
    }

    function testSetRelayerEmitsEvent() external {
        vm.expectEmit(true, true, false, false);
        emit WrappedBNSv2.RelayerUpdated(relayer, alice);
        vm.prank(admin);
        wrapped.setRelayer(alice);
    }

    // -------------------------------------------------------------------------
    // nameToTokenId
    // -------------------------------------------------------------------------

    function testNameToTokenIdIsDeterministic() external view {
        assertEq(wrapped.nameToTokenId(ALICE_NAME), wrapped.nameToTokenId(ALICE_NAME));
    }

    function testDifferentNamesProduceDifferentTokenIds() external view {
        assertNotEq(wrapped.nameToTokenId(ALICE_NAME), wrapped.nameToTokenId(BOB_NAME));
    }

    function testNameToTokenIdMatchesExpectedEncoding() external view {
        uint256 expected = uint256(keccak256(abi.encodePacked(ALICE_NAME)));
        assertEq(wrapped.nameToTokenId(ALICE_NAME), expected);
    }

    // -------------------------------------------------------------------------
    // Adapter integration — end-to-end
    // -------------------------------------------------------------------------

    function testAdapterRegisterAndControlFollowsRelayerSync() external {
        // 1. Relayer bridges alice.btc to alice's EVM address.
        vm.prank(relayer);
        wrapped.syncOwnership(ALICE_NAME, alice);

        uint256 tokenId = wrapped.nameToTokenId(ALICE_NAME);

        // 2. Alice registers an ERC-8004 agent bound to her .btc name.
        vm.prank(alice);
        uint256 agentId =
            adapter.register(IERCAgentBindings.TokenStandard.ERC721, address(wrapped), tokenId, "ipfs://alice-agent");

        // 3. Alice controls the agent.
        assertTrue(adapter.isController(agentId, alice));
        assertFalse(adapter.isController(agentId, bob));

        // 4. Stacks transfer: alice.btc moves to bob. Relayer syncs EVM.
        vm.prank(relayer);
        wrapped.syncOwnership(ALICE_NAME, bob);

        // 5. Bob now controls the ERC-8004 agent — no adapter transaction needed.
        assertFalse(adapter.isController(agentId, alice));
        assertTrue(adapter.isController(agentId, bob));
    }

    function testAdapterControlDropsWhenNameBurned() external {
        vm.prank(relayer);
        wrapped.syncOwnership(ALICE_NAME, alice);

        uint256 tokenId = wrapped.nameToTokenId(ALICE_NAME);

        vm.prank(alice);
        uint256 agentId =
            adapter.register(IERCAgentBindings.TokenStandard.ERC721, address(wrapped), tokenId, "ipfs://alice-agent");

        assertTrue(adapter.isController(agentId, alice));

        // Name expires on Stacks; relayer burns the wrapped token.
        vm.prank(relayer);
        wrapped.burn(ALICE_NAME);

        // After burn, ownerOf reverts on the wrapped token, so any controller-gated
        // adapter operation also reverts. Confirm this by attempting setAgentURI.
        vm.prank(alice);
        vm.expectRevert();
        adapter.setAgentURI(agentId, "ipfs://hijack");

        vm.prank(bob);
        vm.expectRevert();
        adapter.setAgentURI(agentId, "ipfs://hijack");
    }

    function testMultipleNamesCanRegisterSeparateAgents() external {
        vm.prank(relayer);
        wrapped.syncOwnership(ALICE_NAME, alice);
        vm.prank(relayer);
        wrapped.syncOwnership(BOB_NAME, bob);

        uint256 aliceTokenId = wrapped.nameToTokenId(ALICE_NAME);
        uint256 bobTokenId = wrapped.nameToTokenId(BOB_NAME);

        vm.prank(alice);
        uint256 aliceAgent =
            adapter.register(IERCAgentBindings.TokenStandard.ERC721, address(wrapped), aliceTokenId, "ipfs://alice");
        vm.prank(bob);
        uint256 bobAgent =
            adapter.register(IERCAgentBindings.TokenStandard.ERC721, address(wrapped), bobTokenId, "ipfs://bob");

        assertTrue(adapter.isController(aliceAgent, alice));
        assertTrue(adapter.isController(bobAgent, bob));
        assertFalse(adapter.isController(aliceAgent, bob));
        assertFalse(adapter.isController(bobAgent, alice));
    }
}
