// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Messenger} from "../src/Messenger.sol";

/// @dev Test-only factory; no production factory or deployment helper is needed by Messenger.
contract MessengerFactoryHarness {
    function deploy(bytes32 salt) external returns (Messenger) {
        return new Messenger{salt: salt}();
    }

    function move(Messenger token, address recipient, uint256 amount) external {
        require(token.transfer(recipient, amount), "transfer failed");
    }
}

contract MessengerLaunchTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 ether;

    function test_create2MintsEverythingToImmediateFactory() public {
        MessengerFactoryHarness factory = new MessengerFactoryHarness();
        bytes32 salt = keccak256("Messenger factory deployment");
        address predicted = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            address(factory),
                            salt,
                            keccak256(type(Messenger).creationCode)
                        )
                    )
                )
            )
        );
        address caller = makeAddr("launch caller");
        vm.prank(caller, caller);
        Messenger token = factory.deploy(salt);

        assertEq(address(token), predicted);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(factory)), SUPPLY);
        assertEq(token.balanceOf(caller), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }

    function test_launchDistributionClaimsAndPoolTransfersAreExact() public {
        MessengerFactoryHarness factory = new MessengerFactoryHarness();
        Messenger token = factory.deploy(keccak256("distribution"));
        address distributor = makeAddr("distributor");
        address poolManager = makeAddr("pool manager");
        address remainderRecipient = makeAddr("remainder recipient");
        address claimant = makeAddr("claimant");
        address trader = makeAddr("trader");
        uint256 swarm = SUPPLY / 10;
        uint256 pool = SUPPLY * 7 / 10;
        uint256 remainder = SUPPLY - swarm - pool;

        factory.move(token, distributor, swarm);
        factory.move(token, poolManager, pool);
        factory.move(token, remainderRecipient, remainder);
        assertEq(token.balanceOf(address(factory)), 0);
        assertEq(token.balanceOf(distributor), swarm);
        assertEq(token.balanceOf(poolManager), pool);
        assertEq(token.balanceOf(remainderRecipient), remainder);

        vm.prank(distributor);
        assertTrue(token.transfer(claimant, swarm));
        assertEq(token.balanceOf(distributor), 0);
        assertEq(token.balanceOf(claimant), swarm);

        // Exercise the token side of buy/sell settlement, with an ordinary unrestricted trader.
        // This harness does not implement Uniswap pricing or its unlock protocol.
        vm.prank(poolManager);
        assertTrue(token.transfer(trader, 123 ether));
        assertEq(token.balanceOf(trader), 123 ether);
        assertEq(token.balanceOf(poolManager), pool - 123 ether);
        vm.prank(trader);
        assertTrue(token.transfer(poolManager, 123 ether));
        assertEq(token.balanceOf(trader), 0);
        assertEq(token.balanceOf(poolManager), pool);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_runtimeIsDeployableAndHasNoForbiddenOpcodes() public {
        Messenger token = new Messenger();
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576);
        for (uint256 i; i < runtime.length; ++i) {
            uint8 opcode = uint8(runtime[i]);
            if (opcode >= 0x60 && opcode <= 0x7f) {
                i += opcode - 0x5f;
                continue;
            }
            assertTrue(opcode != 0xf4, "DELEGATECALL");
            assertTrue(opcode != 0xf2, "CALLCODE");
            assertTrue(opcode != 0xff, "SELFDESTRUCT");
        }
    }
}
