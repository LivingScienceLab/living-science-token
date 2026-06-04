# CHECKPOINT — Living Science Token (LSL)

_Saved 2026-06-03. Resume from the "NEXT ACTION" section._

## What this project is
A fixed-supply ERC-20 token to be deployed to **Ethereum mainnet**, signed by a **Ledger**
hardware wallet via **Alchemy** RPC, with source hosted on **GitHub (private)** and mirrored
to an existing **Google Cloud Source Repositories (CSR)** repo.

- Name: **Living Science Token** · Symbol: **LSL** · Decimals: **18** · Supply: **1,000,000**
- Features: Fixed supply · Burnable · EIP-2612 Permit · **no owner/admin** (immutable)
- Built on OpenZeppelin v5.6.1, Foundry.

## DONE ✅
- [x] Foundry project scaffolded at `/home/jpj5000/living-science-token`
- [x] Contract: `src/LivingScienceToken.sol`
- [x] Tests: `test/LivingScienceToken.t.sol` — **22 passing** (unit + fuzz + permit reverts/replay + events + domain)
- [x] Deploy script (Ledger): `script/Deploy.s.sol`
- [x] CI: `.github/workflows/test.yml` (pinned to stable Foundry)
- [x] Secrets pattern: `.env.example` (+ `.env` gitignored)
- [x] Slither static analysis: **0 findings**
- [x] Independent review (subagents): contract + deploy + tests all clean
- [x] One-shot push script: `scripts/push-and-mirror.sh`
- [x] Runbook: `PRE-MAINNET-CHECKLIST.md`
- [x] Portable backup: `/home/jpj5000/living-science-token.bundle`
- [x] 3 commits on local `main` (nothing pushed to any remote yet)

## BLOCKED ON (only the user can do this)
Authentication. No GitHub/gcloud credentials exist on disk yet, so nothing has been pushed.

## >>> NEXT ACTION <<<
1. In a terminal on this machine, run: `gh auth login`
   (GitHub.com → HTTPS → Yes → Login with a web browser; paste the device code)
2. Then run: `CSR_URL="https://source.developers.google.com/p/PROJECT/r/REPO" bash scripts/push-and-mirror.sh`
   - For the CSR mirror also run `gcloud auth login` first.
   - Omit `CSR_URL=...` to push to GitHub only.
3. Then follow `PRE-MAINNET-CHECKLIST.md`: Sepolia dry run → verify → mainnet.

## OPEN QUESTIONS for the user
- Is the Ledger **24-word seed phrase backed up offline**?
- Supply stays on the **single Ledger address**, or move to a **multisig (Safe)**?
- Confirm CSR repo URL.

## Tooling locations (this machine)
- Foundry (forge/cast/anvil): `~/.config/.foundry/bin/` (add to PATH)
- gcloud: `~/google-cloud-sdk/bin/gcloud`
- Slither: `~/.slither-venv/bin/slither`
- Node 22, npm, git, gh 2.93 all installed
