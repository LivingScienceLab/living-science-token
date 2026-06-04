// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {LivingScienceToken} from "../src/LivingScienceToken.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract LivingScienceTokenTest is Test {
    LivingScienceToken internal token;

    address internal deployer = makeAddr("deployer");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    uint256 internal constant SUPPLY = 1_000_000 * 1e18;

    // Mirror of the ERC-20 events so we can assert emissions.
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    bytes32 internal constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

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

    /* ------------------------ permit revert paths ------------------- */

    function _permitDigest(address owner, address spender, uint256 value, uint256 nonce, uint256 deadline)
        internal
        view
        returns (bytes32)
    {
        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonce, deadline));
        return keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash));
    }

    function test_PermitRevertsOnExpiredDeadline() public {
        vm.warp(1000);
        uint256 ownerPk = 0xA11CE;
        address owner = vm.addr(ownerPk);
        uint256 deadline = block.timestamp - 1; // already expired
        bytes32 digest = _permitDigest(owner, bob, 1e18, token.nonces(owner), deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPk, digest);

        vm.expectRevert(abi.encodeWithSelector(ERC20Permit.ERC2612ExpiredSignature.selector, deadline));
        token.permit(owner, bob, 1e18, deadline, v, r, s);
    }

    function test_PermitRevertsOnInvalidSignature() public {
        uint256 ownerPk = 0xA11CE;
        address owner = vm.addr(ownerPk);
        uint256 wrongPk = 0xB0B;
        address wrongSigner = vm.addr(wrongPk);
        uint256 deadline = block.timestamp + 1 hours;

        // Sign the owner's permit digest with the WRONG key.
        bytes32 digest = _permitDigest(owner, bob, 1e18, token.nonces(owner), deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongPk, digest);

        vm.expectRevert(abi.encodeWithSelector(ERC20Permit.ERC2612InvalidSigner.selector, wrongSigner, owner));
        token.permit(owner, bob, 1e18, deadline, v, r, s);
    }

    function test_PermitRevertsOnReplay() public {
        uint256 ownerPk = 0xA11CE;
        address owner = vm.addr(ownerPk);
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 digest = _permitDigest(owner, bob, 5e18, token.nonces(owner), deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPk, digest);

        token.permit(owner, bob, 5e18, deadline, v, r, s); // first use succeeds
        assertEq(token.allowance(owner, bob), 5e18);

        // Replaying the same signature fails: the nonce advanced, so ecrecover
        // yields a different address that does not match `owner`.
        vm.expectRevert();
        token.permit(owner, bob, 5e18, deadline, v, r, s);
    }

    /* -------------------- allowance / zero-address ------------------ */

    function test_TransferFromRevertsOnInsufficientAllowance() public {
        vm.prank(deployer);
        token.approve(alice, 100e18);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 100e18, 101e18));
        token.transferFrom(deployer, bob, 101e18);
    }

    function test_TransferToZeroReverts() public {
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1e18);
    }

    function test_ApproveToZeroReverts() public {
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1e18);
    }

    /* ---------------------- burn revert paths ----------------------- */

    function test_BurnRevertsOnInsufficientBalance() public {
        vm.prank(alice); // alice has 0
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        token.burn(1);
    }

    function test_BurnFromRevertsWithoutAllowance() public {
        vm.prank(alice); // no allowance from deployer
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 1e18));
        token.burnFrom(deployer, 1e18);
    }

    /* --------------------- domain + event checks -------------------- */

    function test_DomainSeparator() public view {
        bytes32 expected = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("Living Science Token")),
                keccak256(bytes("1")),
                block.chainid,
                address(token)
            )
        );
        assertEq(token.DOMAIN_SEPARATOR(), expected);
    }

    function test_TransferEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(deployer, alice, 7e18);
        vm.prank(deployer);
        token.transfer(alice, 7e18);
    }

    function test_ApproveEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(deployer, alice, 7e18);
        vm.prank(deployer);
        token.approve(alice, 7e18);
    }
}
