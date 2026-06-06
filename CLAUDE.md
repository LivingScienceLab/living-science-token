# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A single immutable ERC-20 contract, **Living Science Token (LSL)**, intended for a one-time
deployment to Ethereum mainnet signed by a Ledger hardware wallet. This is a deliverable
headed for production with real funds — treat the contract and deploy path as high-stakes and
irreversible. There is no upgrade mechanism; whatever ships is permanent.

## Commands

Foundry's `forge`/`cast`/`anvil` may not be on `PATH` by default; the binaries live in
`~/.config/.foundry/bin/` (and `~/.foundry/bin/`). Add to `PATH` or invoke by full path.

```bash
forge build                       # compile (solc 0.8.24, cancun, optimizer 200 runs)
forge build --sizes               # compile + report bytecode sizes (CI uses this)
forge test -vvv                   # run the full suite
forge test --match-test test_Permit -vvv     # run a single test by name
forge test --match-contract LivingScienceTokenTest    # run one test contract
forge fmt --check                 # formatting gate — CI fails if this fails; run `forge fmt` to fix
forge snapshot                    # regenerate .gas-snapshot
slither .                         # static analysis (~/.slither-venv/bin/slither); expected: 0 findings
```

CI (`.github/workflows/test.yml`) runs, in order: `forge fmt --check` → `forge build --sizes`
→ `forge test -vvv`. Run `forge fmt` before committing or CI will reject the formatting.

## Architecture

The entire token is `src/LivingScienceToken.sol` — it does nothing custom beyond composing
three audited OpenZeppelin v5 mixins and minting once in the constructor:

- `ERC20` — base token, 18 decimals.
- `ERC20Burnable` — `burn` / `burnFrom`; supply can only ever decrease.
- `ERC20Permit` (EIP-2612) — gasless approvals via signature; sets the EIP-712 domain to
  name `"Living Science Token"`, version `"1"`.

Deliberate non-features, each load-bearing for the token's "trustless/immutable" promise — do
not add any of them without explicit instruction:
- **No mint function** — supply is fixed at `INITIAL_SUPPLY` (1,000,000 × 1e18), minted to the
  deployer in the constructor. `_mint` is called exactly once and is never exposed.
- **No owner/admin, no `Ownable`, no pause, no upgradeability** — there are no privileged roles.
- The constructor's only guard is rejecting a zero-address `initialHolder`.

`script/Deploy.s.sol` deploys with `initialHolder = msg.sender`, so **the address that signs the
broadcast receives the entire supply**. For real deploys that signer is a Ledger (`--ledger
--sender <addr>`); no private key is ever read from disk or env.

Because deployment is a plain `CREATE` from deployer `0x7C9eF832417e63F805ccaAbD131741aceEB5Bc1a`
at nonce 0, the contract address is deterministic and identical on every chain:
**`0xe1Eb0f66a15b80f64CA252fbe0CA3087F74A9B08`** (this only holds if the deploy is the deployer's
first outgoing tx on that chain). For a no-signature dry run, drop `--broadcast --ledger` and pass
any `--sender`; add `--rpc-url <net>` to simulate against live chain state and estimate gas.

`test/LivingScienceTokenTest` is the behavioral spec — unit tests, a transfer fuzz test, and
notably the permit revert/replay paths and `DOMAIN_SEPARATOR` / event assertions. The
`test_SupplyNeverIncreases` test encodes the core invariant. If you change the contract, these
tests are the contract of record; keep them green and extend them rather than weakening asserts.

## Dependencies

OpenZeppelin and forge-std are git submodules under `lib/` (see `.gitmodules`), mapped via
`remappings.txt`. After a fresh clone run `git submodule update --init --recursive` (or
`forge install`) or builds will fail with missing imports. Pinned to OpenZeppelin v5.6.1.

## Secrets & deployment flow

- `.env` (gitignored) supplies `SEPOLIA_RPC_URL`, `MAINNET_RPC_URL`, `ETHERSCAN_API_KEY`,
  `LEDGER_SENDER`; `foundry.toml` reads RPC/Etherscan config from these env vars. Never commit
  `.env` or any key, and never print secret values.
- Deploy order is **mandatory**: Sepolia dry run with `--verify` → confirm on Etherscan →
  mainnet. `README.md` and `PRE-MAINNET-CHECKLIST.md` are the authoritative runbooks; defer to
  them for any deploy step and never initiate or suggest skipping the Sepolia stage.
- `scripts/push-and-mirror.sh` is a one-shot to create the private GitHub repo and (optionally)
  add a Google Cloud Source Repositories mirror as a second push URL. It requires `gh auth
  login` (and `gcloud auth login` for the mirror) to have been run by the user first.

## Ledger gotchas (cost real debugging time — read before any signed deploy)

- Use deployer **`0x7C9eF832417e63F805ccaAbD131741aceEB5Bc1a`** = Foundry's **default** path
  `m/44'/60'/0'/0/0`. Deploy with **no derivation-path flags** and it signs cleanly.
- Do **not** use `0x65DA41f1bF3c058bCc74A122f62a247fEEc299c0` (the address `cast wallet list
  --ledger` happens to print first). It sits on a legacy path forge can't auto-resolve →
  `No associated wallet for addresses` errors mid-broadcast.
- On ChromeOS/Crostini: share the Ledger USB into the container, then
  `sudo chown <user> /dev/bus/usb/<BUS>/<DEV>` so `cast`/`forge` reach it without sudo. Device
  must be unlocked, Ethereum app open, **blind signing enabled** (required to sign a deployment).

## Status

`CHECKPOINT.md` tracks project state. **LSL is now DEPLOYED and Etherscan-verified on Ethereum
mainnet** at `0xe1Eb0f66a15b80f64CA252fbe0CA3087F74A9B08` (full 1,000,000 supply on the deployer
Ledger address; deploy tx `0xa67cb272e3be97dc4dcf667ae81deff9442915707ad214445ef2770d2b2f20e2`),
after a complete Sepolia dry run (deploy + verify + transfer + burn). Remaining work is
post-deploy: token distribution and any legal/tax follow-up — not contract changes.
