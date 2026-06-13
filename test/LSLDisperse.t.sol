// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {LivingScienceToken} from "../src/LivingScienceToken.sol";
import {LSLDisperse} from "../src/LSLDisperse.sol";

/// @dev Minimal ERC-20 stub whose `transferFrom` returns false without reverting, to exercise
///      LSLDisperse's non-reverting-failure branch (a standard OZ token always reverts instead).
contract FalseReturningToken {
    function transferFrom(address, address, uint256) external pure returns (bool) {
        return false;
    }
}

contract LSLDisperseTest is Test {
    LivingScienceToken internal token;
    LSLDisperse internal disperser;

    address internal treasurer = makeAddr("treasurer");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");

    uint256 internal constant SUPPLY = 1_000_000e18;

    function setUp() public {
        // Full supply minted to the treasurer (stands in for the Ledger), who approves the helper.
        vm.prank(treasurer);
        token = new LivingScienceToken(treasurer);

        disperser = new LSLDisperse();

        vm.prank(treasurer);
        token.approve(address(disperser), type(uint256).max);
    }

    /* ------------------------------ helpers -------------------------------- */

    function _recipients() internal view returns (address[] memory r) {
        r = new address[](3);
        r[0] = alice;
        r[1] = bob;
        r[2] = carol;
    }

    function _amounts() internal pure returns (uint256[] memory a) {
        a = new uint256[](3);
        a[0] = 100e18;
        a[1] = 250e18;
        a[2] = 50e18; // total 400e18
    }

    /* ------------------------------ happy path ----------------------------- */

    function test_DispersesToAllRecipients() public {
        vm.prank(treasurer);
        disperser.disperse(token, _recipients(), _amounts());

        assertEq(token.balanceOf(alice), 100e18);
        assertEq(token.balanceOf(bob), 250e18);
        assertEq(token.balanceOf(carol), 50e18);
        assertEq(token.balanceOf(treasurer), SUPPLY - 400e18);
        // The helper never retains tokens.
        assertEq(token.balanceOf(address(disperser)), 0);
    }

    function test_ConsumesExactAllowance() public {
        uint256 total = 400e18;
        vm.prank(treasurer);
        token.approve(address(disperser), total); // exact, overwriting the setUp max approval

        vm.prank(treasurer);
        disperser.disperse(token, _recipients(), _amounts());

        assertEq(token.allowance(treasurer, address(disperser)), 0);
    }

    /* ------------------------------ input guards --------------------------- */

    function test_RevertsOnLengthMismatch() public {
        address[] memory r = _recipients(); // length 3
        uint256[] memory a = new uint256[](2);
        a[0] = 1e18;
        a[1] = 2e18;

        vm.prank(treasurer);
        vm.expectRevert(abi.encodeWithSelector(LSLDisperse.LengthMismatch.selector, 3, 2));
        disperser.disperse(token, r, a);
    }

    function test_RevertsOnEmptyBatch() public {
        address[] memory r = new address[](0);
        uint256[] memory a = new uint256[](0);

        vm.prank(treasurer);
        vm.expectRevert(LSLDisperse.EmptyBatch.selector);
        disperser.disperse(token, r, a);
    }

    function test_RevertsWhenTransferReturnsFalse() public {
        FalseReturningToken f = new FalseReturningToken();
        address[] memory r = new address[](1);
        r[0] = alice;
        uint256[] memory a = new uint256[](1);
        a[0] = 1e18;

        vm.prank(treasurer);
        vm.expectRevert(abi.encodeWithSelector(LSLDisperse.TransferFailed.selector, alice, 1e18));
        disperser.disperse(IERC20(address(f)), r, a);
    }

    /* ------------------------------ atomicity ------------------------------ */

    function test_RevertsAtomicallyOnInsufficientBalance() public {
        address poor = makeAddr("poor");
        vm.prank(treasurer);
        token.transfer(poor, 100e18);
        vm.prank(poor);
        token.approve(address(disperser), type(uint256).max);

        address[] memory r = new address[](2);
        r[0] = alice;
        r[1] = bob;
        uint256[] memory a = new uint256[](2);
        a[0] = 60e18;
        a[1] = 60e18; // 120e18 total > poor's 100e18; second leg reverts

        vm.prank(poor);
        vm.expectRevert(); // ERC20InsufficientBalance from the token
        disperser.disperse(token, r, a);

        // Atomic: the first (otherwise-valid) leg was rolled back too — nobody received anything.
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(poor), 100e18);
    }

    function test_RevertsAtomicallyOnInsufficientAllowance() public {
        vm.prank(treasurer);
        token.approve(address(disperser), 400e18 - 1); // one wei short of the total

        vm.prank(treasurer);
        vm.expectRevert(); // ERC20InsufficientAllowance on the final leg
        disperser.disperse(token, _recipients(), _amounts());

        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(carol), 0);
        assertEq(token.balanceOf(treasurer), SUPPLY);
    }

    /* -------------------------------- fuzz --------------------------------- */

    function testFuzz_DispersesArbitraryAmounts(uint256 a0, uint256 a1, uint256 a2) public {
        a0 = bound(a0, 1, 100_000e18);
        a1 = bound(a1, 1, 100_000e18);
        a2 = bound(a2, 1, 100_000e18);
        uint256 total = a0 + a1 + a2; // <= 300_000e18, well under supply

        address[] memory r = _recipients();
        uint256[] memory a = new uint256[](3);
        a[0] = a0;
        a[1] = a1;
        a[2] = a2;

        vm.prank(treasurer);
        disperser.disperse(token, r, a);

        assertEq(token.balanceOf(alice), a0);
        assertEq(token.balanceOf(bob), a1);
        assertEq(token.balanceOf(carol), a2);
        assertEq(token.balanceOf(treasurer), SUPPLY - total);
        assertEq(token.balanceOf(address(disperser)), 0);
    }
}
