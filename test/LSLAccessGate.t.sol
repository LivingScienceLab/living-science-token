// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {LivingScienceToken} from "../src/LivingScienceToken.sol";
import {LSLAccessGate} from "../src/LSLAccessGate.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

contract LSLAccessGateTest is Test {
    LivingScienceToken internal token;
    LSLAccessGate internal gate;

    address internal owner = makeAddr("owner");
    address internal treasury = makeAddr("treasury");
    address internal operator = makeAddr("operator");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    bytes32 internal constant API = keccak256("dataset-api");
    bytes32 internal constant SUB = keccak256("platform-subscription");

    uint128 internal constant USE_PRICE = 10e18; // 10 LSL per use
    uint128 internal constant SUB_PRICE = 100e18; // 100 LSL per period
    uint64 internal constant PERIOD = 30 days;

    // Mirrors for event assertions.
    event Purchased(
        address indexed user,
        bytes32 indexed id,
        LSLAccessGate.AccessModel model,
        uint256 quantity,
        uint256 cost,
        uint64 expiry
    );
    event Consumed(address indexed user, bytes32 indexed id, uint256 amount, uint256 remaining);
    event SinkSet(LSLAccessGate.SpentSink sink, address indexed treasury);

    function setUp() public {
        // Token: full supply minted to `owner`, who also owns the gate.
        vm.prank(owner);
        token = new LivingScienceToken(owner);

        gate = new LSLAccessGate(address(token), LSLAccessGate.SpentSink.Treasury, treasury, owner);

        // Register a per-use and a subscription resource.
        vm.startPrank(owner);
        gate.setResource(API, LSLAccessGate.AccessModel.PerUse, USE_PRICE, 0, true);
        gate.setResource(SUB, LSLAccessGate.AccessModel.Subscription, SUB_PRICE, PERIOD, true);
        gate.setOperator(operator, true);
        // Fund the buyers.
        token.transfer(alice, 10_000e18);
        token.transfer(bob, 10_000e18);
        vm.stopPrank();

        vm.prank(alice);
        token.approve(address(gate), type(uint256).max);
        vm.prank(bob);
        token.approve(address(gate), type(uint256).max);
    }

    /* --------------------------- constructor ------------------------- */

    function test_ConstructorState() public view {
        assertEq(address(gate.token()), address(token));
        assertEq(uint8(gate.sink()), uint8(LSLAccessGate.SpentSink.Treasury));
        assertEq(gate.treasury(), treasury);
        assertEq(gate.owner(), owner);
    }

    function test_ConstructorRevertsOnZeroToken() public {
        vm.expectRevert(LSLAccessGate.ZeroAddress.selector);
        new LSLAccessGate(address(0), LSLAccessGate.SpentSink.Burn, address(0), owner);
    }

    function test_ConstructorRevertsWhenTreasurySinkHasZeroTreasury() public {
        vm.expectRevert(LSLAccessGate.TreasuryRequired.selector);
        new LSLAccessGate(address(token), LSLAccessGate.SpentSink.Treasury, address(0), owner);
    }

    function test_ConstructorAllowsBurnSinkWithZeroTreasury() public {
        LSLAccessGate g = new LSLAccessGate(address(token), LSLAccessGate.SpentSink.Burn, address(0), owner);
        assertEq(uint8(g.sink()), uint8(LSLAccessGate.SpentSink.Burn));
        assertEq(g.treasury(), address(0));
    }

    /* ------------------------ admin / access ------------------------- */

    function test_SetResourceOnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        gate.setResource(API, LSLAccessGate.AccessModel.PerUse, 1e18, 0, true);
    }

    function test_SetSinkRequiresTreasury() public {
        vm.prank(owner);
        vm.expectRevert(LSLAccessGate.TreasuryRequired.selector);
        gate.setSink(LSLAccessGate.SpentSink.Treasury, address(0));
    }

    function test_SetSinkToBurnEmits() public {
        vm.expectEmit(true, false, false, true, address(gate));
        emit SinkSet(LSLAccessGate.SpentSink.Burn, address(0));
        vm.prank(owner);
        gate.setSink(LSLAccessGate.SpentSink.Burn, address(0));
        assertEq(uint8(gate.sink()), uint8(LSLAccessGate.SpentSink.Burn));
    }

    function test_SetOperatorOnlyOwnerAndZeroCheck() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        gate.setOperator(bob, true);

        vm.prank(owner);
        vm.expectRevert(LSLAccessGate.ZeroAddress.selector);
        gate.setOperator(address(0), true);
    }

    /* --------------------------- per-use ----------------------------- */

    function test_PurchasePerUseAddsCreditsAndChargesTreasury() public {
        uint256 cost = gate.quote(API, 5);
        assertEq(cost, 5 * USE_PRICE);

        vm.expectEmit(true, true, false, true, address(gate));
        emit Purchased(alice, API, LSLAccessGate.AccessModel.PerUse, 5, cost, 0);

        vm.prank(alice);
        gate.purchase(API, 5);

        assertEq(gate.credits(alice, API), 5);
        assertTrue(gate.hasAccess(alice, API));
        assertEq(token.balanceOf(treasury), cost);
        assertEq(token.balanceOf(alice), 10_000e18 - cost);
        assertEq(token.balanceOf(address(gate)), 0); // gate never retains tokens
    }

    function test_ConsumeByOperatorDecrementsCredits() public {
        vm.prank(alice);
        gate.purchase(API, 5);

        vm.expectEmit(true, true, false, true, address(gate));
        emit Consumed(alice, API, 2, 3);
        vm.prank(operator);
        gate.consume(alice, API, 2);

        assertEq(gate.credits(alice, API), 3);
    }

    function test_ConsumeRevertsForNonOperator() public {
        vm.prank(alice);
        gate.purchase(API, 1);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(LSLAccessGate.NotOperator.selector, bob));
        gate.consume(alice, API, 1);
    }

    function test_ConsumeRevertsOnInsufficientCredits() public {
        vm.prank(alice);
        gate.purchase(API, 1);
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(LSLAccessGate.InsufficientCredits.selector, alice, API, 1, 2));
        gate.consume(alice, API, 2);
    }

    function test_ConsumeRevertsOnWrongModel() public {
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(LSLAccessGate.WrongAccessModel.selector, SUB));
        gate.consume(alice, SUB, 1);
    }

    /* ------------------------- subscription -------------------------- */

    function test_PurchaseSubscriptionSetsExpiry() public {
        vm.warp(1_000_000);
        uint256 cost = gate.quote(SUB, 2);

        vm.prank(alice);
        gate.purchase(SUB, 2);

        uint64 expected = uint64(block.timestamp) + 2 * PERIOD;
        assertEq(gate.accessExpiry(alice, SUB), expected);
        assertTrue(gate.hasAccess(alice, SUB));
        assertEq(token.balanceOf(treasury), cost);
    }

    function test_SubscriptionExtendsFromCurrentExpiryWhenStillActive() public {
        vm.warp(1_000_000);
        vm.prank(alice);
        gate.purchase(SUB, 1);
        uint64 first = gate.accessExpiry(alice, SUB);

        // Still active: a second purchase stacks on top of the existing expiry.
        vm.warp(1_000_000 + 1 days);
        vm.prank(alice);
        gate.purchase(SUB, 1);
        assertEq(gate.accessExpiry(alice, SUB), first + PERIOD);
    }

    function test_SubscriptionRebasesFromNowWhenExpired() public {
        vm.warp(1_000_000);
        vm.prank(alice);
        gate.purchase(SUB, 1);

        // Let it lapse, then renew: expiry should rebase off `now`, not the stale value.
        vm.warp(1_000_000 + PERIOD + 10 days);
        assertFalse(gate.hasAccess(alice, SUB));
        vm.prank(alice);
        gate.purchase(SUB, 1);
        assertEq(gate.accessExpiry(alice, SUB), uint64(block.timestamp) + PERIOD);
        assertTrue(gate.hasAccess(alice, SUB));
    }

    /* ----------------------------- burn ------------------------------ */

    function test_BurnSinkReducesTotalSupply() public {
        vm.prank(owner);
        gate.setSink(LSLAccessGate.SpentSink.Burn, address(0));

        uint256 supplyBefore = token.totalSupply();
        uint256 cost = gate.quote(API, 3);

        vm.prank(alice);
        gate.purchase(API, 3);

        assertEq(token.totalSupply(), supplyBefore - cost);
        assertEq(token.balanceOf(treasury), 0);
        assertEq(token.balanceOf(address(gate)), 0);
        assertEq(gate.credits(alice, API), 3);
    }

    /* ---------------------------- permit ----------------------------- */

    function test_PurchaseWithPermit() public {
        uint256 pk = 0xA11CE;
        address carol = vm.addr(pk);
        vm.prank(owner);
        token.transfer(carol, 1_000e18);

        uint256 cost = gate.quote(API, 4);
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                carol,
                address(gate),
                cost,
                token.nonces(carol),
                deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);

        // No prior approve() — the permit grants the allowance inline.
        vm.prank(carol);
        gate.purchaseWithPermit(API, 4, cost, deadline, v, r, s);

        assertEq(gate.credits(carol, API), 4);
        assertEq(token.balanceOf(treasury), cost);
    }

    /* ----------------------- pause / reverts ------------------------- */

    function test_PurchaseRevertsWhenPaused() public {
        vm.prank(owner);
        gate.pause();
        vm.prank(alice);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        gate.purchase(API, 1);
    }

    function test_PurchaseRevertsOnZeroQuantity() public {
        vm.prank(alice);
        vm.expectRevert(LSLAccessGate.ZeroQuantity.selector);
        gate.purchase(API, 0);
    }

    function test_PurchaseRevertsOnInactiveResource() public {
        vm.prank(owner);
        gate.setResourceActive(API, false);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(LSLAccessGate.UnknownOrInactiveResource.selector, API));
        gate.purchase(API, 1);
    }

    function test_PurchaseRevertsOnUnknownResource() public {
        bytes32 ghost = keccak256("does-not-exist");
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(LSLAccessGate.UnknownOrInactiveResource.selector, ghost));
        gate.purchase(ghost, 1);
    }

    function test_PurchaseRevertsOnInsufficientAllowance() public {
        address dan = makeAddr("dan");
        vm.prank(owner);
        token.transfer(dan, 1_000e18);
        // dan never approved the gate.
        vm.prank(dan);
        vm.expectRevert();
        gate.purchase(API, 1);
    }

    /* ----------------------------- fuzz ------------------------------ */

    function testFuzz_PurchasePerUse(uint256 qty) public {
        qty = bound(qty, 1, 1_000); // 1000 * 10 LSL = 10_000 LSL = alice's balance
        uint256 cost = gate.quote(API, qty);
        vm.assume(cost <= token.balanceOf(alice));

        vm.prank(alice);
        gate.purchase(API, qty);

        assertEq(gate.credits(alice, API), qty);
        assertEq(token.balanceOf(treasury), cost);
    }
}
