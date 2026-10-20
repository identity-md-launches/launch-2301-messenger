// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Messenger} from "../src/Messenger.sol";

/// @dev All generated transfers stay within this closed actor set, making conservation measurable.
contract MessengerHandler is Test {
    uint256 private constant SUPPLY = 1_000_000_000 ether;
    Messenger public immutable token;
    address[4] public actors;

    // Independent ledger: seed it from the specification, then update only for authorized
    // operations. Never copy balances or allowances back from the implementation.
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(Messenger token_) {
        token = token_;
        actors =
            [address(this), makeAddr("actor one"), makeAddr("actor two"), makeAddr("actor three")];
        expectedBalance[address(this)] = SUPPLY;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        amount = bound(amount, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        _recordTransfer(from, to, amount);
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        _approve(owner, spender, amount);
    }

    /// @dev Explicitly visit revocations and the finite/infinite allowance boundary often.
    function approveBoundary(uint256 ownerSeed, uint256 spenderSeed, uint256 boundary) external {
        uint256[5] memory amounts =
            [uint256(0), 1, SUPPLY, type(uint256).max - 1, type(uint256).max];
        _approve(
            actors[ownerSeed % actors.length],
            actors[spenderSeed % actors.length],
            amounts[boundary % amounts.length]
        );
    }

    function transferFrom(uint256 fromSeed, uint256 toSeed, uint256 spenderSeed, uint256 amount)
        external
    {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 allowanceBefore = expectedAllowance[from][spender];
        uint256 balance = expectedBalance[from];
        amount = bound(amount, 0, balance < allowanceBefore ? balance : allowanceBefore);
        vm.prank(spender);
        assertTrue(token.transferFrom(from, to, amount));
        _recordTransfer(from, to, amount);
        if (allowanceBefore != type(uint256).max) {
            expectedAllowance[from][spender] -= amount;
        }
        assertEq(
            token.allowance(from, spender),
            allowanceBefore == type(uint256).max ? allowanceBefore : allowanceBefore - amount
        );
    }

    /// @dev Full-balance and self transfers remain reachable even after long sequences.
    function transferFullBalance(uint256 fromSeed, uint256 toSeed) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 amount = expectedBalance[from];
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        _recordTransfer(from, to, amount);
    }

    function transferOverBalance(uint256 fromSeed, uint256 toSeed, uint256 excess) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[from];
        uint256 amount = balance + bound(excess, 1, type(uint256).max - balance);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount
            )
        );
        vm.prank(from);
        token.transfer(to, amount);
        // Expected state deliberately stays unchanged for all rejected operations.
    }

    function transferOverAllowance(
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 toSeed,
        uint256 approved,
        uint256 excess
    ) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        approved = bound(approved, 0, SUPPLY - 1);
        _approve(owner, spender, approved);
        uint256 amount = approved + bound(excess, 1, SUPPLY - approved);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, amount
            )
        );
        vm.prank(spender);
        token.transferFrom(owner, to, amount);
    }

    /// @dev A failed transfer must roll back even an allowance already consumed internally.
    function transferFromOverBalance(
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 toSeed,
        uint256 excess,
        bool infinite
    ) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[owner];
        uint256 amount = balance + bound(excess, 1, type(uint256).max - balance);
        _approve(owner, spender, infinite ? type(uint256).max : amount);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount
            )
        );
        vm.prank(spender);
        token.transferFrom(owner, to, amount);
    }

    function transferToZero(uint256 ownerSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        amount = bound(amount, 0, expectedBalance[owner]);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
        );
        vm.prank(owner);
        token.transfer(address(0), amount);
    }

    function transferFromToZero(
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 amount,
        bool infinite
    ) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        amount = bound(amount, 0, expectedBalance[owner]);
        _approve(owner, spender, infinite ? type(uint256).max : amount);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
        );
        vm.prank(spender);
        token.transferFrom(owner, address(0), amount);
    }

    function approveZeroSpender(uint256 ownerSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0))
        );
        vm.prank(owner);
        token.approve(address(0), amount);
    }

    function _approve(address owner, address spender, uint256 amount) private {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
        assertEq(token.allowance(owner, spender), amount);
    }

    function _recordTransfer(address from, address to, uint256 amount) private {
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract MessengerInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 ether;
    Messenger private token;
    MessengerHandler private handler;

    function setUp() public {
        token = new Messenger();
        handler = new MessengerHandler(token);
        assertTrue(token.transfer(address(handler), SUPPLY));
        // Start with several funded actors so delegated and ordinary transfers can do real work.
        handler.transfer(0, 1, SUPPLY / 4);
        handler.transfer(0, 2, SUPPLY / 4);
        handler.transfer(0, 3, SUPPLY / 4);
        bytes4[] memory selectors = new bytes4[](11);
        selectors[0] = MessengerHandler.transfer.selector;
        selectors[1] = MessengerHandler.approve.selector;
        selectors[2] = MessengerHandler.transferFrom.selector;
        selectors[3] = MessengerHandler.approveBoundary.selector;
        selectors[4] = MessengerHandler.transferFullBalance.selector;
        selectors[5] = MessengerHandler.transferOverBalance.selector;
        selectors[6] = MessengerHandler.transferOverAllowance.selector;
        selectors[7] = MessengerHandler.transferFromOverBalance.selector;
        selectors[8] = MessengerHandler.transferToZero.selector;
        selectors[9] = MessengerHandler.transferFromToZero.selector;
        selectors[10] = MessengerHandler.approveZeroSpender.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_supplyAndBalancesAreConserved() public view {
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            sum += token.balanceOf(handler.actors(i));
        }
        assertEq(sum, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(this)), 0);
    }

    /// @dev Conservation alone would miss transfers credited to the wrong holder.
    function invariant_eachBalanceMatchesAuthorizedTransfers() public view {
        for (uint256 i; i < 4; ++i) {
            address actor = handler.actors(i);
            assertEq(
                token.balanceOf(actor), handler.expectedBalance(actor), "holder ledger mismatch"
            );
        }
    }

    /// @dev Includes self approvals, unrelated owner/spender pairs, revocation and failed spends.
    function invariant_allowancesMatchApprovalsAndSuccessfulSpends() public view {
        for (uint256 i; i < 4; ++i) {
            address owner = handler.actors(i);
            for (uint256 j; j < 4; ++j) {
                address spender = handler.actors(j);
                assertEq(
                    token.allowance(owner, spender),
                    handler.expectedAllowance(owner, spender),
                    "allowance ledger mismatch"
                );
            }
            assertEq(token.allowance(owner, address(0)), 0);
            assertEq(token.allowance(address(0), owner), 0);
        }
    }

    /// @dev Pin a useful sequence as well as fuzzing it: spend, fail, revoke, fail, reapprove, spend.
    function test_handlerExercisesNonzeroSpendingAndRecoveryAfterReverts() public {
        handler.approve(0, 1, 10);
        handler.transferFrom(0, 2, 1, 4);
        assertEq(token.balanceOf(handler.actors(2)), SUPPLY / 4 + 4);
        assertEq(token.allowance(handler.actors(0), handler.actors(1)), 6);

        handler.transferFromToZero(0, 1, 6, false);
        assertEq(token.allowance(handler.actors(0), handler.actors(1)), 6);
        handler.approveBoundary(0, 1, 0);
        handler.transferOverAllowance(0, 1, 2, 0, 1);
        handler.approveBoundary(0, 1, 4);
        handler.transferFrom(0, 2, 1, 6);
        assertEq(token.allowance(handler.actors(0), handler.actors(1)), type(uint256).max);
        assertEq(token.balanceOf(handler.actors(2)), SUPPLY / 4 + 10);

        invariant_supplyAndBalancesAreConserved();
        invariant_eachBalanceMatchesAuthorizedTransfers();
        invariant_allowancesMatchApprovalsAndSuccessfulSpends();
    }
}
