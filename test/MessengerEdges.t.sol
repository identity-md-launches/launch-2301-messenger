// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Messenger} from "src/Messenger.sol";

/// @dev Complements the basic ERC-20 and launch tests with arithmetic and authorization edges.
/// forge-config: default.fuzz.runs = 1000
contract MessengerEdgesTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 ether;
    Messenger private token;
    address private alice;
    address private bob;
    address private spender;
    address private otherSpender;

    function setUp() public {
        token = new Messenger();
        alice = makeAddr("edge alice");
        bob = makeAddr("edge bob");
        spender = makeAddr("edge spender");
        otherSpender = makeAddr("edge other spender");
    }

    function test_oneWeiCanBeTransferredAndSpentWithExactApproval() public {
        assertTrue(token.transfer(alice, 1));
        vm.prank(alice);
        assertTrue(token.approve(spender, 1));
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(alice, bob, 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 1));

        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_entireSupplyCanBeSpentWithExactApprovalOnlyOnce() public {
        assertTrue(token.approve(spender, SUPPLY));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.allowance(address(this), spender), 0);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1)
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferOfMaximumAmountRevertsWithoutOverflowOrMinting() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                address(this),
                SUPPLY,
                type(uint256).max
            )
        );
        token.transfer(alice, type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_selfTransferStillRequiresSufficientBalance() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1
            )
        );
        token.transfer(address(this), SUPPLY + 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_delegatedSelfTransferCannotBypassBalanceCheck() public {
        assertTrue(token.approve(spender, SUPPLY + 1));
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1
            )
        );
        vm.prank(spender);
        token.transferFrom(address(this), address(this), SUPPLY + 1);
        assertEq(token.allowance(address(this), spender), SUPPLY + 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_maximumAllowanceDoesNotAuthorizeAnOverdraft() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                address(this),
                SUPPLY,
                type(uint256).max
            )
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, type(uint256).max);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_largestFiniteAllowanceIsConsumed() public {
        assertTrue(token.approve(spender, type(uint256).max - 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max - 2);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, SUPPLY - 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max - 1 - SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice) + token.balanceOf(bob), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_infiniteApprovalCanBeReducedAndRevoked() public {
        assertTrue(token.approve(spender, type(uint256).max));
        assertTrue(token.approve(spender, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), 0);

        assertTrue(token.approve(spender, type(uint256).max));
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Approval(address(this), spender, 0);
        assertTrue(token.approve(spender, 0));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1)
        );
        vm.prank(spender);
        token.transferFrom(address(this), bob, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.allowance(address(this), spender), 0);
    }

    function test_holderMustAuthorizeItselfToUseTransferFrom() public {
        assertTrue(token.transfer(alice, 1));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 1)
        );
        vm.prank(alice);
        token.transferFrom(alice, bob, 1);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(bob), 0);

        vm.startPrank(alice);
        assertTrue(token.approve(alice, 1));
        assertTrue(token.transferFrom(alice, bob, 1));
        vm.stopPrank();
        assertEq(token.allowance(alice, alice), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 1);
    }

    function test_approvalBeforeFundingCannotCreateTokensAndWorksAfterFunding() public {
        vm.prank(alice);
        assertTrue(token.approve(spender, 1));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1)
        );
        vm.prank(spender);
        token.transferFrom(alice, bob, 1);
        assertEq(token.allowance(alice, spender), 1);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);

        assertTrue(token.transfer(alice, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 1));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 1);
        assertEq(token.allowance(alice, spender), 0);
    }

    function test_zeroDelegatedTransferEmitsEventWithoutConsumingApproval() public {
        vm.prank(alice);
        assertTrue(token.approve(spender, 7));
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(alice, bob, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.allowance(alice, spender), 7);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroAmountCannotBypassInvalidReceiverOrSpender() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0))
        );
        token.approve(address(0), 0);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
        );
        vm.prank(spender);
        token.transferFrom(address(this), address(0), 0);
        assertEq(token.allowance(address(this), address(0)), 0);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// @dev Zero-address pranks exercise defensive guards; no real account is assigned this address.
    function test_zeroSenderCannotTransferOrApprove() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidSender.selector, address(0))
        );
        vm.prank(address(0));
        token.transfer(alice, 0);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0))
        );
        vm.prank(address(0));
        token.approve(spender, type(uint256).max);
        assertEq(token.allowance(address(0), spender), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_tokensSentToTokenContractRemainPartOfSupply() public {
        assertTrue(token.transfer(address(token), 1));
        assertTrue(token.approve(spender, SUPPLY - 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), address(token), SUPPLY - 1));
        assertEq(token.balanceOf(address(token)), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_delegatedOverdraftRestoresAllowanceAndCanRecover(
        uint256 funded,
        uint256 excess,
        bool infinite
    ) public {
        funded = bound(funded, 0, SUPPLY);
        uint256 amount = funded + bound(excess, 1, type(uint256).max - funded);
        uint256 approved = infinite ? type(uint256).max : amount;
        assertTrue(token.transfer(alice, funded));
        vm.prank(alice);
        assertTrue(token.approve(spender, approved));

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, alice, funded, amount
            )
        );
        vm.prank(spender);
        token.transferFrom(alice, bob, amount);
        assertEq(token.allowance(alice, spender), approved);
        assertEq(token.balanceOf(alice), funded);
        assertEq(token.balanceOf(bob), 0);

        // The reverted call must leave the approval usable, including when the holder is empty.
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, funded));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), funded);
        assertEq(token.balanceOf(address(this)), SUPPLY - funded);
        assertEq(
            token.allowance(alice, spender),
            approved == type(uint256).max ? approved : approved - funded
        );
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferRoundTripRestoresBalancesAndApprovals(
        uint256 funded,
        uint256 amount,
        uint256 approved
    ) public {
        funded = bound(funded, 0, SUPPLY);
        amount = bound(amount, 0, funded);
        assertTrue(token.transfer(alice, funded));
        vm.prank(alice);
        assertTrue(token.approve(spender, approved));
        vm.prank(alice);
        assertTrue(token.transfer(bob, amount));
        vm.prank(bob);
        assertTrue(token.transfer(alice, amount));
        assertEq(token.balanceOf(alice), funded);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - funded);
        assertEq(token.allowance(alice, spender), approved);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_splitDelegatedTransferMatchesSingleTransfer(
        uint256 total,
        uint256 first,
        uint256 approved
    ) public {
        total = bound(total, 0, SUPPLY);
        first = bound(first, 0, total);
        approved = bound(approved, total, type(uint256).max);
        Messenger single = new Messenger();
        assertTrue(single.approve(spender, approved));
        assertTrue(token.approve(spender, approved));

        vm.startPrank(spender);
        assertTrue(single.transferFrom(address(this), alice, total));
        assertTrue(token.transferFrom(address(this), alice, first));
        assertTrue(token.transferFrom(address(this), alice, total - first));
        vm.stopPrank();

        assertEq(token.balanceOf(alice), single.balanceOf(alice));
        assertEq(token.balanceOf(address(this)), single.balanceOf(address(this)));
        assertEq(token.allowance(address(this), spender), single.allowance(address(this), spender));
        assertEq(token.balanceOf(alice), total);
        assertEq(token.balanceOf(alice) + token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(single.totalSupply(), SUPPLY);
    }

    function testFuzz_replacingApprovalDoesNotAffectOtherOwnerOrSpender(
        uint256 original,
        uint256 replacement,
        uint256 otherOwnerApproval,
        uint256 otherSpenderApproval
    ) public {
        vm.prank(alice);
        assertTrue(token.approve(spender, original));
        vm.prank(bob);
        assertTrue(token.approve(spender, otherOwnerApproval));
        vm.prank(alice);
        assertTrue(token.approve(otherSpender, otherSpenderApproval));
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Approval(alice, spender, replacement);
        vm.prank(alice);
        assertTrue(token.approve(spender, replacement));
        // Repeating an approval is idempotent and does not add it to the previous value.
        vm.prank(alice);
        assertTrue(token.approve(spender, replacement));

        assertEq(token.allowance(alice, spender), replacement);
        assertEq(token.allowance(bob, spender), otherOwnerApproval);
        assertEq(token.allowance(alice, otherSpender), otherSpenderApproval);
        assertEq(token.allowance(spender, alice), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_invalidRecipientRollsBackAllowanceAndCanRecover(
        uint256 amount,
        uint256 approved
    ) public {
        amount = bound(amount, 0, SUPPLY);
        approved = bound(approved, amount, type(uint256).max);
        assertTrue(token.approve(spender, approved));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
        );
        vm.prank(spender);
        token.transferFrom(address(this), address(0), amount);
        assertEq(token.allowance(address(this), spender), approved);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);

        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, amount));
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(
            token.allowance(address(this), spender),
            approved == type(uint256).max ? approved : approved - amount
        );
        assertEq(token.totalSupply(), SUPPLY);
    }
}
