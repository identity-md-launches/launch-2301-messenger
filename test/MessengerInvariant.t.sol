// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Messenger} from "../src/Messenger.sol";

/// @dev All generated transfers stay within this closed actor set, making conservation measurable.
contract MessengerHandler is Test {
    Messenger public immutable token;
    address[4] public actors;

    constructor(Messenger token_) {
        token = token_;
        actors =
            [address(this), makeAddr("actor one"), makeAddr("actor two"), makeAddr("actor three")];
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        amount = bound(amount, 0, token.balanceOf(from));
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        assertEq(token.allowance(owner, spender), amount);
    }

    function transferFrom(uint256 fromSeed, uint256 toSeed, uint256 spenderSeed, uint256 amount)
        external
    {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 allowanceBefore = token.allowance(from, spender);
        uint256 balance = token.balanceOf(from);
        amount = bound(amount, 0, balance < allowanceBefore ? balance : allowanceBefore);
        vm.prank(spender);
        assertTrue(token.transferFrom(from, to, amount));
        assertEq(
            token.allowance(from, spender),
            allowanceBefore == type(uint256).max ? allowanceBefore : allowanceBefore - amount
        );
    }
}

contract MessengerInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 ether;
    Messenger private token;
    MessengerHandler private handler;

    function setUp() public {
        token = new Messenger();
        handler = new MessengerHandler(token);
        assertTrue(token.transfer(address(handler), SUPPLY));
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = MessengerHandler.transfer.selector;
        selectors[1] = MessengerHandler.approve.selector;
        selectors[2] = MessengerHandler.transferFrom.selector;
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
    }
}
