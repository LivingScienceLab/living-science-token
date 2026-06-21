// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/* ----------------------------- minimal Uniswap v3 surface ----------------------------- */
// v3-periphery is solc 0.7.x and cannot be imported under 0.8.24, so we declare just the
// functions we call. Addresses below are the canonical Uniswap v3 mainnet deployments.

interface IERC20Like {
    function approve(address spender, uint256 value) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function decimals() external view returns (uint8);
}

interface INonfungiblePositionManager {
    function createAndInitializePoolIfNecessary(address token0, address token1, uint24 fee, uint160 sqrtPriceX96)
        external
        payable
        returns (address pool);

    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    function mint(MintParams calldata params)
        external
        payable
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
}

interface IUniswapV3PoolLike {
    function slot0()
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        );
}

/// @title Seed the LSL / USDC Uniswap v3 pool with a full-range position.
/// @notice Bootstraps a tradeable market for Living Science Token (LSL):
///         creates (if needed) and initializes the 1% LSL/USDC pool at a chosen opening
///         price, then mints a single **full-range** liquidity position from the broadcaster
///         (your Ledger). Full range = no rebalancing, behaves like a constant-product pool.
///
/// @dev    Recalibrated default params (see project notes): open at $0.10/LSL, seed
///         100,000 LSL (10% of supply) + 10,000 USDC → ~$20k depth, $100k FDV, 1% fee tier.
///         Override any value via environment variables (all optional):
///           SEED_LSL_WHOLE   (default 100000)   whole LSL to deposit
///           SEED_USDC_WHOLE  (default 10000)    whole USDC to deposit
///           LSL_TOKEN        (default mainnet LSL)
///           USDC_TOKEN       (default mainnet USDC)
///         The opening price is implied by the ratio: price = USDC_WHOLE / LSL_WHOLE.
///
/// Forge SIMULATES by default (no on-chain effect). Always fork-simulate first:
///   forge script script/SeedUniV3Pool.s.sol:SeedUniV3Pool \
///     --rpc-url mainnet --sender <YOUR_LEDGER_ADDRESS> -vvvv
///
/// Broadcast for real ONLY after the simulation reads back the right price + amounts
/// (spends real LSL + USDC + ETH gas, and is effectively irreversible):
///   forge script script/SeedUniV3Pool.s.sol:SeedUniV3Pool \
///     --rpc-url mainnet --ledger --sender <YOUR_LEDGER_ADDRESS> --broadcast -vvvv
///
/// SECURITY: a fresh pool is snipeable the block it is funded. Broadcast through a private
/// transaction (e.g. Flashbots Protect RPC) so bots cannot front-run the seeding.
contract SeedUniV3Pool is Script {
    // Canonical Uniswap v3 mainnet contracts.
    INonfungiblePositionManager constant NPM =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);

    // LSL (18 decimals) and USDC (6 decimals) mainnet addresses (overridable via env).
    address constant LSL_DEFAULT = 0xe1Eb0f66a15b80f64CA252fbe0CA3087F74A9B08;
    address constant USDC_DEFAULT = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    uint24 constant FEE = 10000; // 1% tier
    // Full range, snapped to the 1%-tier tick spacing (200): multiples of 200 within ±887272.
    int24 constant MIN_TICK = -887200;
    int24 constant MAX_TICK = 887200;

    // Allowed drift between the price we intend and the pool's actual price after init.
    // Non-zero only matters if the pool already exists at a different price (we then abort).
    uint256 constant PRICE_TOLERANCE_BPS = 100; // 1%

    function run() external {
        address lsl = vm.envOr("LSL_TOKEN", LSL_DEFAULT);
        address usdc = vm.envOr("USDC_TOKEN", USDC_DEFAULT);
        uint256 lslWhole = vm.envOr("SEED_LSL_WHOLE", uint256(100_000));
        uint256 usdcWhole = vm.envOr("SEED_USDC_WHOLE", uint256(10_000));

        // Token ordering, raw amounts, and the init price are computed by the pure `plan`
        // helper so the exact logic `run` broadcasts is unit-testable without balances.
        (address token0, address token1, uint256 amount0, uint256 amount1, uint160 sqrtPriceX96) = plan(
            lsl, usdc, IERC20Like(lsl).decimals(), IERC20Like(usdc).decimals(), lslWhole, usdcWhole
        );

        console2.log("Seeding LSL/USDC v3 pool (1%% fee, full range)");
        console2.log("  opening price (USDC per LSL, milli-USD):", (usdcWhole * 1000) / lslWhole);
        console2.log("  LSL to deposit (whole):", lslWhole);
        console2.log("  USDC to deposit (whole):", usdcWhole);
        console2.log("  token0:", token0);
        console2.log("  token1:", token1);

        vm.startBroadcast();

        IERC20Like(token0).approve(address(NPM), amount0);
        IERC20Like(token1).approve(address(NPM), amount1);

        address pool = NPM.createAndInitializePoolIfNecessary(token0, token1, FEE, sqrtPriceX96);

        // Guard: if the pool already existed at a materially different price, abort before we
        // pour liquidity into a mispriced market (createAndInitialize is a no-op on an existing
        // pool, so our intended price would silently not apply).
        (uint160 actualSqrtPrice,,,,,,) = IUniswapV3PoolLike(pool).slot0();
        _requireClose(actualSqrtPrice, sqrtPriceX96);

        (uint256 tokenId,, uint256 used0, uint256 used1) = NPM.mint(
            INonfungiblePositionManager.MintParams({
                token0: token0,
                token1: token1,
                fee: FEE,
                tickLower: MIN_TICK,
                tickUpper: MAX_TICK,
                amount0Desired: amount0,
                amount1Desired: amount1,
                // We initialize the pool at exactly our ratio, so both sides are consumed in
                // full; a small tolerance absorbs integer-liquidity rounding dust.
                amount0Min: (amount0 * (10_000 - PRICE_TOLERANCE_BPS)) / 10_000,
                amount1Min: (amount1 * (10_000 - PRICE_TOLERANCE_BPS)) / 10_000,
                recipient: msg.sender,
                deadline: block.timestamp + 30 minutes
            })
        );

        vm.stopBroadcast();

        console2.log("  pool:", pool);
        console2.log("  position tokenId:", tokenId);
        console2.log("  amount0 used:", used0);
        console2.log("  amount1 used:", used1);
    }

    /* ------------------------------- pure helpers (unit-tested) ------------------------------- */

    /// @notice Decide token0/token1 ordering, raw deposit amounts, and the pool init price.
    /// @dev The exact decision `run` broadcasts, factored out so it is testable without on-chain
    ///      balances. Uniswap orders tokens by address (token0 < token1); raw amounts fold in each
    ///      token's decimals; the init price follows from the resulting amount1/amount0 ratio.
    function plan(
        address lsl,
        address usdc,
        uint8 lslDecimals,
        uint8 usdcDecimals,
        uint256 lslWhole,
        uint256 usdcWhole
    )
        public
        pure
        returns (address token0, address token1, uint256 amount0, uint256 amount1, uint160 sqrtPriceX96)
    {
        uint256 lslRaw = lslWhole * (10 ** lslDecimals);
        uint256 usdcRaw = usdcWhole * (10 ** usdcDecimals);
        (token0, token1, amount0, amount1) =
            lsl < usdc ? (lsl, usdc, lslRaw, usdcRaw) : (usdc, lsl, usdcRaw, lslRaw);
        sqrtPriceX96 = computeSqrtPriceX96(amount0, amount1);
    }

    /// @notice sqrtPriceX96 for a pool holding `amount1` of token1 against `amount0` of token0.
    /// @dev Uniswap price = token1/token0 (raw units). sqrtPriceX96 = sqrt(price) * 2**96, i.e.
    ///      sqrt(price * 2**192). `mulDiv` keeps the (amount1 * 2**192) product at full 512-bit
    ///      precision so it never overflows before the divide. Decimal scaling is already baked
    ///      into the raw amounts, so no separate decimals term is needed here.
    function computeSqrtPriceX96(uint256 amount0, uint256 amount1) public pure returns (uint160) {
        require(amount0 > 0 && amount1 > 0, "zero amount");
        uint256 priceX192 = Math.mulDiv(amount1, 1 << 192, amount0);
        uint256 s = Math.sqrt(priceX192);
        require(s <= type(uint160).max, "sqrtPrice overflow");
        return uint160(s);
    }

    function _requireClose(uint160 actual, uint160 expected) internal pure {
        uint256 hi = uint256(expected) * (10_000 + PRICE_TOLERANCE_BPS) / 10_000;
        uint256 lo = uint256(expected) * (10_000 - PRICE_TOLERANCE_BPS) / 10_000;
        require(actual <= hi && actual >= lo, "pool already initialized at a different price");
    }
}
