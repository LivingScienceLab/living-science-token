# LP Seed Runbook — LSL/USDC Uniswap v3

Bootstraps a tradeable market for LSL by creating and seeding a **Uniswap v3
full-range** position. Read this whole file before broadcasting — the seed
transaction sets LSL's public opening price and is effectively irreversible.

## Parameters (recalibrated default)

| Param | Value | Notes |
| --- | --- | --- |
| Pair | LSL / **USDC** | dollar-denominated price; clean LLC accounting |
| Opening price | **$0.10 / LSL** | ⇒ $100k fully-diluted valuation (1M supply) |
| LSL tranche | **100,000 LSL** | 10% of supply — *not* the whole 1M |
| USDC paired | **10,000 USDC** | forced by price: 100,000 × $0.10 |
| Fee tier | **1%** | correct tier for an illiquid, volatile token |
| Range | **full range** | no rebalancing; behaves like a constant-product pool |
| Pool depth | ~$20k | ≈ +10% spot impact on a $500 buy |

Override via env if adjusting: `SEED_LSL_WHOLE`, `SEED_USDC_WHOLE`. The opening
price is implied by the ratio `SEED_USDC_WHOLE / SEED_LSL_WHOLE`.

## Before you broadcast (in order)

- [ ] **Securities counsel.** Standing up a public secondary market for a token
      you sell to fund operations is a securities question, not just tax. Get
      this cleared *before* broadcasting. (The CPA covers tax basis, not this.)
- [ ] Decide consciously: this commits 10% of supply and exposes the USDC to the
      "buy-desk-on-the-way-down" risk (a dump drains ~⅓ of the USDC; see notes).
- [ ] **Fund the Ledger first:** ≥ 100,000 LSL **and** ≥ 10,000 USDC **and** gas
      ETH must be in the Ledger address *before* the simulation in step 1 — the
      script reverts on insufficient balance before it ever reaches the mint, so
      an unfunded "simulation" proves nothing about the happy path.

## 1. Verify the broadcast path

Two complementary checks — run both:

**(a) Balance-independent end-to-end** — the mainnet-fork test deals balances and
exercises create + initialize + mint against live Uniswap, asserting the pool
opens within 0.1% of $0.10:

```bash
forge test --match-contract SeedUniV3PoolTest -vv   # needs MAINNET_RPC_URL
```

**(b) Fork-simulate the actual `run()`** (only meaningful once the Ledger is
funded — see the checklist above):

```bash
forge script script/SeedUniV3Pool.s.sol:SeedUniV3Pool \
  --rpc-url mainnet --sender <YOUR_LEDGER_ADDRESS> -vvvv
```

Read the logged opening price + token0/token1 + amounts; they must match the
table above. The script **aborts** if the pool already exists at a different
price (the `pool already initialized at a different price` guard), so you can
never pour liquidity into a mispriced market.

## 2. Broadcast (real LSL + USDC + gas — irreversible)

Broadcast through a **private transaction** so bots cannot front-run the seeding
of a fresh, thin pool. Use a Flashbots Protect RPC as the `--rpc-url`:

```bash
forge script script/SeedUniV3Pool.s.sol:SeedUniV3Pool \
  --rpc-url https://rpc.flashbots.net \
  --ledger --sender <YOUR_LEDGER_ADDRESS> --broadcast -vvvv
```

## 3. Verify after seeding

- [ ] The logged pool address shows the position on the Uniswap UI at ~$0.10.
- [ ] The position NFT is held by your Ledger address.
- [ ] A tiny test buy moves the price roughly as expected (~+10% spot per $500).

## Notes / risk

- **The pool is a passive sell desk up, buy desk down.** Price up → it converts
  LSL→USDC (treasury accrues funding). Price down → it spends your USDC buying
  back LSL; reserves drain. Seed only a tranche you accept running both ways.
- **Add liquidity later, don't front-load.** No affordable seed makes a fresh
  pool snipe-proof; start modest + private, deepen as real volume proves demand.
- **Treasury yield is a separate, deferred layer.** Don't deploy accumulated
  USDC into Aave/Sky/etc. until idle cash exceeds ~6–12 months runway and the
  yield clears gas + smart-contract risk. Until then it stays plain USDC.
