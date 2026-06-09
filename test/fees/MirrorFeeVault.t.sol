// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MirrorFeeVault} from "../../src/fees/MirrorFeeVault.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @dev A recipient that rejects ETH, to exercise the FeeForwardFailed path.
contract RejectingRecipient {
    receive() external payable {
        revert("no");
    }
}

contract MirrorFeeVaultTest is Test {
    MirrorFeeVault internal vault;

    address internal owner = makeAddr("owner");
    address internal multisig = makeAddr("multisig");
    address internal user = makeAddr("user");

    uint256 internal constant INITIAL_FEE = 0.001 ether;
    uint256 internal constant MAX_FEE = 0.01 ether;

    string internal constant NAME = "alice.btc";

    function setUp() external {
        vault = new MirrorFeeVault(owner, multisig, INITIAL_FEE, MAX_FEE);
        vm.deal(user, 1 ether);
    }

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    function testConstructorState() external view {
        assertEq(vault.owner(), owner);
        assertEq(vault.feeRecipient(), multisig);
        assertEq(vault.mirrorFee(), INITIAL_FEE);
        assertEq(vault.maxFee(), MAX_FEE);
    }

    function testConstructorRevertsOnZeroRecipient() external {
        vm.expectRevert(MirrorFeeVault.ZeroAddress.selector);
        new MirrorFeeVault(owner, address(0), INITIAL_FEE, MAX_FEE);
    }

    function testConstructorRevertsIfInitialFeeAboveMax() external {
        vm.expectRevert(abi.encodeWithSelector(MirrorFeeVault.FeeTooHigh.selector, MAX_FEE + 1, MAX_FEE));
        new MirrorFeeVault(owner, multisig, MAX_FEE + 1, MAX_FEE);
    }

    // -------------------------------------------------------------------------
    // requestMirror
    // -------------------------------------------------------------------------

    function testRequestMirrorForwardsFeeToRecipient() external {
        uint256 before = multisig.balance;
        vm.prank(user);
        vault.requestMirror{value: INITIAL_FEE}(NAME, user);
        assertEq(multisig.balance - before, INITIAL_FEE);
        // vault holds no balance
        assertEq(address(vault).balance, 0);
    }

    function testRequestMirrorEmitsEvent() external {
        vm.expectEmit(true, true, true, true);
        emit MirrorFeeVault.MirrorRequested(keccak256(bytes(NAME)), NAME, user, user, INITIAL_FEE);
        vm.prank(user);
        vault.requestMirror{value: INITIAL_FEE}(NAME, user);
    }

    function testRequestMirrorRevertsIfUnderpaid() external {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(MirrorFeeVault.InsufficientFee.selector, INITIAL_FEE - 1, INITIAL_FEE));
        vault.requestMirror{value: INITIAL_FEE - 1}(NAME, user);
    }

    function testOverpaymentForwardedAsTip() external {
        uint256 paid = INITIAL_FEE + 0.0005 ether;
        uint256 before = multisig.balance;
        vm.prank(user);
        vault.requestMirror{value: paid}(NAME, user);
        assertEq(multisig.balance - before, paid);
    }

    function testRequestMirrorFreeWhenFeeZero() external {
        vm.prank(owner);
        vault.setMirrorFee(0);
        vm.prank(user);
        vault.requestMirror{value: 0}(NAME, user); // must not revert
    }

    function testRequestMirrorRevertsIfRecipientRejects() external {
        RejectingRecipient bad = new RejectingRecipient();
        MirrorFeeVault v = new MirrorFeeVault(owner, address(bad), INITIAL_FEE, MAX_FEE);
        vm.deal(user, 1 ether);
        vm.prank(user);
        vm.expectRevert(MirrorFeeVault.FeeForwardFailed.selector);
        v.requestMirror{value: INITIAL_FEE}(NAME, user);
    }

    // -------------------------------------------------------------------------
    // Admin
    // -------------------------------------------------------------------------

    function testSetMirrorFee() external {
        vm.prank(owner);
        vault.setMirrorFee(0.002 ether);
        assertEq(vault.mirrorFee(), 0.002 ether);
    }

    function testSetMirrorFeeRevertsAboveMax() external {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(MirrorFeeVault.FeeTooHigh.selector, MAX_FEE + 1, MAX_FEE));
        vault.setMirrorFee(MAX_FEE + 1);
    }

    function testSetMirrorFeeOnlyOwner() external {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        vault.setMirrorFee(0.002 ether);
    }

    function testSetFeeRecipient() external {
        address newRecipient = makeAddr("newRecipient");
        vm.prank(owner);
        vault.setFeeRecipient(newRecipient);
        assertEq(vault.feeRecipient(), newRecipient);
    }

    function testSetFeeRecipientRevertsOnZero() external {
        vm.prank(owner);
        vm.expectRevert(MirrorFeeVault.ZeroAddress.selector);
        vault.setFeeRecipient(address(0));
    }

    function testSetFeeRecipientOnlyOwner() external {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        vault.setFeeRecipient(user);
    }

    // -------------------------------------------------------------------------
    // Fuzz — the maxFee ceiling can never be exceeded via setMirrorFee
    // -------------------------------------------------------------------------

    function testFuzzSetMirrorFeeRespectsCap(uint256 newFee) external {
        vm.prank(owner);
        if (newFee > MAX_FEE) {
            vm.expectRevert(abi.encodeWithSelector(MirrorFeeVault.FeeTooHigh.selector, newFee, MAX_FEE));
            vault.setMirrorFee(newFee);
        } else {
            vault.setMirrorFee(newFee);
            assertEq(vault.mirrorFee(), newFee);
            assertLe(vault.mirrorFee(), vault.maxFee());
        }
    }
}
