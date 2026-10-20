// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Messenger} from "../src/Messenger.sol";

contract MessengerTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 ether;

    Messenger private token;
    address private alice;
    address private bob;
    address private spender;

    function setUp() public {
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        spender = makeAddr("spender");
        token = new Messenger();
    }

    function test_metadataAndInitialSupply() public view {
        assertEq(token.name(), "Messenger");
        assertEq(token.symbol(), "MAIL");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(address(this), spender), 0);
    }

    function test_constructorEmitsMintTransfer() public {
        vm.expectEmit(true, true, false, true);
        emit IERC20.Transfer(address(0), address(this), SUPPLY);
        new Messenger();
    }

    function test_transferMovesExactAmountAndEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(address(this), alice, 10 ether);
        assertTrue(token.transfer(alice, 10 ether));
        assertEq(token.balanceOf(address(this)), SUPPLY - 10 ether);
        assertEq(token.balanceOf(alice), 10 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_entireSupplyCanMoveAndReturn() public {
        assertTrue(token.transfer(alice, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        vm.prank(alice);
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(alice, bob, 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_selfTransferPreservesBalance() public {
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferToZeroReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
        );
        token.transfer(address(0), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroTransferToZeroReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
        );
        token.transfer(address(0), 0);
    }

    function test_transferFromEmptyAccountReverts() public {
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1)
        );
        token.transfer(bob, 1);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_approveSetsAllowanceAndEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Approval(address(this), spender, 42 ether);
        assertTrue(token.approve(spender, 42 ether));
        assertEq(token.allowance(address(this), spender), 42 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_approveReplacesAllowanceAndCanRevoke() public {
        assertTrue(token.approve(spender, 42 ether));
        assertTrue(token.approve(spender, 7 ether));
        assertEq(token.allowance(address(this), spender), 7 ether);
        assertTrue(token.approve(spender, 0));

        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1)
        );
        token.transferFrom(address(this), alice, 1);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_approveZeroSpenderReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0))
        );
        token.approve(address(0), 1);
    }

    function test_transferFromConsumesAllowanceAndEmitsTransfer() public {
        assertTrue(token.approve(spender, 42 ether));
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(address(this), alice, 7 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 7 ether));
        assertEq(token.allowance(address(this), spender), 35 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 7 ether);
        assertEq(token.balanceOf(alice), 7 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferFromCanExhaustAllowance() public {
        assertTrue(token.approve(spender, 42 ether));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 42 ether));
        assertEq(token.allowance(address(this), spender), 0);
        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1)
        );
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(alice), 42 ether);
    }

    function test_infiniteAllowanceIsNotReduced() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.startPrank(spender);
        assertTrue(token.transferFrom(address(this), alice, 7 ether));
        assertTrue(token.transferFrom(address(this), bob, 8 ether));
        vm.stopPrank();
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY - 15 ether);
        assertEq(token.balanceOf(alice), 7 ether);
        assertEq(token.balanceOf(bob), 8 ether);
    }

    function test_unapprovedSpenderCannotTransfer() public {
        assertTrue(token.approve(spender, 42 ether));
        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1)
        );
        token.transferFrom(address(this), bob, 1);
        assertEq(token.allowance(address(this), spender), 42 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_deployerCannotSpendHoldersTokensWithoutApproval() public {
        assertTrue(token.transfer(alice, 42 ether));
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1
            )
        );
        token.transferFrom(alice, address(this), 1);
        assertEq(token.balanceOf(alice), 42 ether);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 42 ether));
        assertEq(token.balanceOf(bob), 42 ether);
    }

    function test_failedTransferFromPreservesAllowanceAndBalances() public {
        vm.prank(alice);
        assertTrue(token.approve(spender, 42 ether));
        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 42 ether
            )
        );
        token.transferFrom(alice, bob, 42 ether);
        assertEq(token.allowance(alice, spender), 42 ether);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_transferFromToZeroRevertsAndPreservesAllowance() public {
        assertTrue(token.approve(spender, 42 ether));
        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
        );
        token.transferFrom(address(this), address(0), 42 ether);
        assertEq(token.allowance(address(this), spender), 42 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferFromZeroSenderReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0))
        );
        token.transferFrom(address(0), alice, 0);
    }

    function test_zeroTransferFromNeedsNoAllowance() public {
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_selfTransferFromConsumesAllowanceWithoutChangingBalance() public {
        assertTrue(token.approve(spender, 42 ether));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), address(this), 42 ether));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_noMintBurnOrAdministrativeEntrypoints() public {
        assertTrue(token.transfer(alice, 42 ether));
        bytes[] memory calls = new bytes[](13);
        calls[0] = abi.encodeWithSignature("mint(address,uint256)", bob, 1);
        calls[1] = abi.encodeWithSignature("mint(uint256)", 1);
        calls[2] = abi.encodeWithSignature("mint()");
        calls[3] = abi.encodeWithSignature("burn(uint256)", 1);
        calls[4] = abi.encodeWithSignature("burnFrom(address,uint256)", alice, 1);
        calls[5] = abi.encodeWithSignature("pause()");
        calls[6] = abi.encodeWithSignature("blacklist(address)", alice);
        calls[7] = abi.encodeWithSignature("freeze(address)", alice);
        calls[8] = abi.encodeWithSignature("seize(address)", alice);
        calls[9] = abi.encodeWithSignature("transferOwnership(address)", bob);
        calls[10] = abi.encodeWithSignature("upgradeTo(address)", bob);
        calls[11] = abi.encodeWithSignature("initialize(address)", bob);
        calls[12] = abi.encodeWithSignature("setMinter(address)", bob);

        for (uint256 i; i < calls.length; ++i) {
            (bool deployerSucceeded,) = address(token).call(calls[i]);
            assertFalse(deployerSucceeded, "deployer reached an unsupported entrypoint");
            vm.prank(bob);
            (bool strangerSucceeded,) = address(token).call(calls[i]);
            assertFalse(strangerSucceeded, "stranger reached an unsupported entrypoint");
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(alice), 42 ether);
        assertEq(token.balanceOf(bob), 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 42 ether));
        assertEq(token.balanceOf(bob), 42 ether);
    }

    function test_rejectsNativeCurrency() public {
        vm.deal(address(this), 1 ether);
        (bool success,) = address(token).call{value: 1 ether}("");
        assertFalse(success);
        assertEq(address(token).balance, 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferConservesSupply(address recipient, uint256 amount) public {
        vm.assume(recipient != address(0) && recipient != address(this));
        amount = bound(amount, 0, SUPPLY);
        assertTrue(token.transfer(recipient, amount));
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferMoreThanBalanceReverts(uint256 balance, uint256 excess) public {
        balance = bound(balance, 0, SUPPLY);
        excess = bound(excess, 1, type(uint256).max - balance);
        assertTrue(token.transfer(alice, balance));
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, balance + excess
            )
        );
        token.transfer(bob, balance + excess);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_delegatedTransfer(uint256 approved, uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        approved = bound(approved, amount, type(uint256).max);
        assertTrue(token.approve(spender, approved));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, amount));
        assertEq(
            token.allowance(address(this), spender),
            approved == type(uint256).max ? approved : approved - amount
        );
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferMoreThanAllowanceReverts(uint256 approved, uint256 excess) public {
        approved = bound(approved, 0, SUPPLY - 1);
        excess = bound(excess, 1, SUPPLY - approved);
        assertTrue(token.approve(spender, approved));
        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                spender,
                approved,
                approved + excess
            )
        );
        token.transferFrom(address(this), alice, approved + excess);
        assertEq(token.allowance(address(this), spender), approved);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }
}
