// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {
    SeedUniV3Pool,
    IERC20Like,
    INonfungiblePositionManager,
    IUniswapV3PoolLike
} from "../script/SeedUniV3Pool.s.sol";

contract SeedUniV3PoolTest is Test {
    SeedUniV3Pool internal seeder;

    address constant LSL = 0xe1Eb0f66a15b80f64CA252fbe0CA3087F74A9B08; // 18 decimals
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // 6 decimals
    address constant NPM = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    uint24 constant FEE = 10000;
    int24 constant MIN_TICK = -887200;
    int24 constant MAX_TICK = 887200;

    // Recalibrated default seed: $0.10/LSL → token0=USDC raw, token1=LSL raw.
    uint256 constant AMOUNT0 = 10_000 * 1e6; // 10,000 USDC
    uint256 constant AMOUNT1 = 100_000 * 1e18; // 100,000 LSL

    function setUp() public {
        seeder = new SeedUniV3Pool();
        // Keep the helper deployed across a later vm.createSelectFork (which otherwise
        // swaps in mainnet state and wipes locally-deployed code).
        vm.makePersistent(address(seeder));
    }

    /* ------------------------------ pure math (no fork) ------------------------------ */

    function test_usdc_is_token0() public pure {
        // Uniswap orders by address; the script relies on USDC < LSL.
        assertTrue(USDC < LSL, "expected USDC to sort before LSL");
    }

    function test_sqrtPrice_roundtrips_to_target_ratio() public view {
        uint160 sp = seeder.computeSqrtPriceX96(AMOUNT0, AMOUNT1);
        // Decode pool price = (sqrtP^2) / 2^192 = token1/token0 in raw units.
        uint256 price = Math.mulDiv(uint256(sp), uint256(sp), 1 << 192);
        uint256 expected = AMOUNT1 / AMOUNT0; // 1e23 / 1e10 = 1e13
        // == $0.10/LSL: 1e13 raw-LSL per raw-USDC * 10^(6-18) = 10 LSL per USDC.
        assertApproxEqRel(price, expected, 1e14); // within 0.01%
    }

    function test_higher_usd_price_means_lower_token1_per_token0() public view {
        uint160 at10c = seeder.computeSqrtPriceX96(AMOUNT0, AMOUNT1); // $0.10
        uint160 at20c = seeder.computeSqrtPriceX96(AMOUNT0 * 2, AMOUNT1); // $0.20 (more USDC/LSL)
        // token0 is USDC, so doubling USDC halves token1/token0 → lower sqrtPrice.
        assertLt(at20c, at10c);
    }

    function test_reverts_on_zero_amount() public {
        vm.expectRevert(bytes("zero amount"));
        seeder.computeSqrtPriceX96(0, AMOUNT1);
    }

    /// @dev Exercises the exact ordering/amount/price logic `run()` broadcasts (the fork test
    ///      re-implements it inline; this pins `run()`'s own code path for the default config).
    function test_plan_orders_amounts_and_price_for_default_config() public view {
        (address token0, address token1, uint256 amount0, uint256 amount1, uint160 sqrtPriceX96) =
            seeder.plan(LSL, USDC, 18, 6, 100_000, 10_000);
        assertEq(token0, USDC, "token0 should be USDC");
        assertEq(token1, LSL, "token1 should be LSL");
        assertEq(amount0, AMOUNT0, "amount0 = 10,000 USDC raw");
        assertEq(amount1, AMOUNT1, "amount1 = 100,000 LSL raw");
        assertEq(sqrtPriceX96, seeder.computeSqrtPriceX96(AMOUNT0, AMOUNT1));
    }

    /* ------------------------------ end-to-end on a mainnet fork ------------------------------ */
    // Runs only when MAINNET_RPC_URL is set; otherwise it self-skips so CI/offline stays green.

    function test_fork_seed_initializes_pool_at_target_price() public {
        string memory rpc = vm.envOr("MAINNET_RPC_URL", string(""));
        if (bytes(rpc).length == 0) {
            emit log("MAINNET_RPC_URL unset - skipping fork seed test");
            return;
        }
        vm.createSelectFork(rpc);

        address sender = makeAddr("seeder");
        deal(USDC, sender, AMOUNT0);
        deal(LSL, sender, AMOUNT1);

        uint160 sp = seeder.computeSqrtPriceX96(AMOUNT0, AMOUNT1);

        vm.startPrank(sender);
        IERC20Like(USDC).approve(NPM, AMOUNT0);
        IERC20Like(LSL).approve(NPM, AMOUNT1);
        address pool = INonfungiblePositionManager(NPM).createAndInitializePoolIfNecessary(USDC, LSL, FEE, sp);
        (uint256 tokenId,, uint256 used0, uint256 used1) = INonfungiblePositionManager(NPM).mint(
            INonfungiblePositionManager.MintParams({
                token0: USDC,
                token1: LSL,
                fee: FEE,
                tickLower: MIN_TICK,
                tickUpper: MAX_TICK,
                amount0Desired: AMOUNT0,
                amount1Desired: AMOUNT1,
                amount0Min: AMOUNT0 * 99 / 100,
                amount1Min: AMOUNT1 * 99 / 100,
                recipient: sender,
                deadline: block.timestamp + 30 minutes
            })
        );
        vm.stopPrank();

        (uint160 actual,,,,,,) = IUniswapV3PoolLike(pool).slot0();
        assertApproxEqRel(uint256(actual), uint256(sp), 1e15); // pool opened within 0.1% of target
        assertGt(tokenId, 0);
        assertGt(used0, 0);
        assertGt(used1, 0);
        // Liquidity actually left the seeder's wallet.
        assertLt(IERC20Like(USDC).balanceOf(sender), AMOUNT0);
        assertLt(IERC20Like(LSL).balanceOf(sender), AMOUNT1);
    }
}
