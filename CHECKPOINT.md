# CHECKPOINT — Living Science Token (LSL)

_Saved 2026-06-06; updated 2026-06-12 (LSLDisperse deployed to mainnet). Resume from the "NEXT ACTION" section._

## What this project is
A fixed-supply ERC-20 token, **deployed to Ethereum mainnet**, signed by a **Ledger**
hardware wallet via **Alchemy** RPC, with source on **GitHub (private)**.

- Name: **Living Science Token** · Symbol: **LSL** · Decimals: **18** · Supply: **1,000,000**
- Features: Fixed supply · Burnable · EIP-2612 Permit · **no owner/admin** (immutable)
- Built on OpenZeppelin v5.6.1, Foundry.

## On-chain facts (mainnet)
- LSL token: **`0xe1Eb0f66a15b80f64CA252fbe0CA3087F74A9B08`** — Etherscan-verified.
- Deploy tx: `0xa67cb272e3be97dc4dcf667ae81deff9442915707ad214445ef2770d2b2f20e2`.
- Deployer / holder of full 1,000,000 supply: Ledger **`0x7C9eF832417e63F805ccaAbD131741aceEB5Bc1a`**
  (Foundry default path `m/44'/60'/0'/0/0`).
- **LSLDisperse** batch helper: **`0x2d6fEC5f0d3611Ec9BFe7b633bD180B49d17Fcdd`** — Etherscan-verified
  (deployed + verified 2026-06-12). Deploy tx
  `0x9ecf3fb12ef8023c8cece1ed74491734fbb49081bba62593a7a765eca0094ade`, block 25305047, 235,364 gas.
  Address is stored in `.env` as `LSL_DISPERSE_ADDRESS`; set it as env `LSL_DISPERSE` for `DisperseBatch`.

## DONE ✅
- [x] Contract `src/LivingScienceToken.sol` + tests (22 passing) + Slither (0 findings)
- [x] Independent subagent review: contract + deploy + tests clean
- [x] CI green (`forge fmt --check` → `forge build --sizes` → `forge test`)
- [x] **Pushed to GitHub** `LivingScienceLab/living-science-token` — `main` in sync, nothing unpushed
- [x] Sepolia dry run: deploy + verify + transfer + burn — all confirmed
- [x] **Mainnet deploy + Etherscan verification** (see on-chain facts above)
- [x] Distribution tooling: `script/Distribute.s.sol` + gated `scripts/distribute.sh`
      (simulate-first, Ledger-signed); template `distribution.example.json`
- [x] Single-batch distribution path: `src/LSLDisperse.sol` (stateless/ownerless atomic batch
      helper, 8 tests) + `script/DeployDisperse.s.sol` + `script/DisperseBatch.s.sol` + gated
      `scripts/disperse.sh` — fans out in one tx (2 Ledger sigs total, not N).
      **Deployed + Etherscan-verified on mainnet 2026-06-12** at
      `0x2d6fEC5f0d3611Ec9BFe7b633bD180B49d17Fcdd`. NOTE: deployed straight to mainnet without the
      usual Sepolia rehearsal, at the user's explicit instruction.
- [x] `LEGAL-TAX-CHECKLIST.md` — topics to take to securities counsel + tax pro

## NOT done / current frontier ⏳
- [ ] **Distribution not started** — no `distribution.json` exists yet (only the example).
      The entire supply still sits on the single Ledger address; nothing is sold or traded.
- [ ] **Legal/tax engagement open** — per `LEGAL-TAX-CHECKLIST.md`, decide distribution model
      + entity + counsel review *before* moving any tokens.
- [x] **Custody decided (2026-06-06): supply stays on the single Ledger key** — no Safe/multisig
      migration. Makes the offline seed-phrase backup the critical single point of failure.
- [x] **LSLDisperse verified on Etherscan (2026-06-12)** — done with a fresh V2 API key (the old V1
      key was rejected by Etherscan's V2 API; `.env` now holds a working V2 key).

## >>> NEXT ACTION <<<
Distribution is gated on legal/tax, not on code. The tooling is ready; the blocker is decisions.
1. Engage a **securities attorney** + **crypto-literate tax pro**; decide the distribution model.
2. When ready to move tokens: `cp distribution.example.json distribution.json`, fill in real
   recipients + whole-LSL amounts, then **dry-run first**: `scripts/distribute.sh mainnet`
   (it simulates against live state, prints a preview, and asks before any Ledger-signed broadcast).
3. Preserve every distribution tx + date + FMV for tax records (`broadcast/` is the audit trail).

## OPEN QUESTIONS for the user
- ~~Is the Ledger 24-word seed phrase backed up offline?~~ **CONFIRMED: yes, backed up offline (2026-06-06).**
- ~~Supply stays on the single Ledger address, or move to a multisig (Safe)?~~ **DECIDED: single Ledger key (2026-06-06).**
- Issuing entity: still to be decided with securities counsel. "Living Science Lab" is a brand/project name,
  not a separate legal entity.

## Tooling locations (this machine)
- Foundry (forge/cast/anvil): `~/.config/.foundry/bin/` (add to PATH)
- gcloud: `~/google-cloud-sdk/bin/gcloud`
- Slither: `~/.slither-venv/bin/slither`
- Node 22, npm, git, gh 2.93 all installed
