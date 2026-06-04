// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {LivingScienceToken} from "../src/LivingScienceToken.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

contract LivingScienceTokenTest is Test {
    LivingScienceToken internal token;

    address internal deployer = makeAddr("deployer");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    uint256 internal constant SUPPLY = 1_000_000 * 1e18;

    function setUp() public {
        vm.prank(deployer);
        token = new LivingScienceToken(deployer);
    }

    /* --------------------------- metadata --------------------------- */

    function test_Metadata() public view {
        assertEq(token.name(), "Living Science Token");
        assertEq(token.symbol(), "LSL");
        assertEq(token.decimals(), 18);
    }

    function test_TotalSupplyAndInitialBalance() public view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
    }

    function test_ConstructorRevertsOnZeroAddress() public {
        vm.expectRevert(bytes("LSL: initial holder is zero address"));
        new LivingScienceToken(address(0));
    }

    /* --------------------------- transfers -------------------------- */

    function test_Transfer() public {
        vm.prank(deployer);
        token.transfer(alice, 100e18);
        assertEq(token.balanceOf(alice), 100e18);
        assertEq(token.balanceOf(deployer), SUPPLY - 100e18);
    }

    function test_TransferRevertsOnInsufficientBalance() public {
        vm.prank(alice); // alice has 0
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        token.transfer(bob, 1);
    }

    function test_ApproveAndTransferFrom() public {
        vm.prank(deployer);
        token.approve(alice, 500e18);
        assertEq(token.allowance(deployer, alice), 500e18);

        vm.prank(alice);
        token.transferFrom(deployer, bob, 300e18);

        assertEq(token.balanceOf(bob), 300e18);
        assertEq(token.allowance(deployer, alice), 200e18);
    }

    /* ----------------------------- burn ----------------------------- */

    function test_Burn() public {
        vm.prank(deployer);
        token.burn(1_000e18);
        assertEq(token.totalSupply(), SUPPLY - 1_000e18);
        assertEq(token.balanceOf(deployer), SUPPLY - 1_000e18);
    }

    function test_BurnFrom() public {
        vm.prank(deployer);
        token.approve(alice, 1_000e18);

        vm.prank(alice);
        token.burnFrom(deployer, 1_000e18);

        assertEq(token.totalSupply(), SUPPLY - 1_000e18);
        assertEq(token.allowance(deployer, alice), 0);
    }

    /* ---------------------------- permit ---------------------------- */

    function test_Permit() public {
        uint256 ownerPk = 0xA11CE;
        address owner = vm.addr(ownerPk);

        // fund owner so the approval is meaningful
        vm.prank(deployer);
        token.transfer(owner, 50e18);

        uint256 value = 25e18;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = token.nonces(owner);

        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                owner,
                bob,
                value,
                nonce,
                deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPk, digest);

        token.permit(owner, bob, value, deadline, v, r, s);

        assertEq(token.allowance(owner, bob), value);
        assertEq(token.nonces(owner), nonce + 1);
    }

    /* ------------------ supply is fixed (no minting) ----------------- */

    /// @dev There is no public/external mint function. This test documents that
    ///      the only way supply changes is downward, via burning.
    function test_SupplyNeverIncreases() public {
        uint256 before = token.totalSupply();

        vm.prank(deployer);
        token.transfer(alice, 10e18);
        assertEq(token.totalSupply(), before, "transfers must not change supply");

        vm.prank(alice);
        token.burn(10e18);
        assertEq(token.totalSupply(), before - 10e18, "burning reduces supply");
        assertLt(token.totalSupply(), before, "supply only ever goes down");
    }

    /* ------------------------- fuzz: transfer ----------------------- */

    function testFuzz_Transfer(uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        vm.prank(deployer);
        token.transfer(alice, amount);
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(deployer), SUPPLY - amount);
    }
}
