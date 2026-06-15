# CHECKPOINT — Living Science Token (LSL)

_Saved 2026-06-06; updated 2026-06-14 — **AccessGate milestone COMPLETE** (tag `accessgate-v1`): spend-to-access
live on mainnet + SIWE-secured gatekeeper + reverse proxy + deployment kit + Node 24-ready CI. Resume from the
"NEXT ACTION" section (remaining AccessGate work is ops/business, not code)._

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
- **LSLAccessGate** (spend-to-access): **`0x14c129b8D22491a2cCE9Be36137eC8d9B9b31Db5`** — Etherscan-verified
  (deployed 2026-06-13). SINK=Treasury, treasury=owner=Ledger `0x7C9e…Bc1a`. Deploy tx
  `0xeeb75d87029f94664ecf0828f69d290343b0571594d69695026b496e1ee0d00f`, block 25306831.
  Resource set (2026-06-13): **`research-access`** = Subscription, 50 LSL / 30 days, active
  (tx `0x279f8e40c6f49d548719c86720e40d8eb8c1aa694ba0cf66579cabb982dd0106`).
  **Resource ID encoding:** the `bytes32 id` is the **string `"research-access"` right-padded**
  (`cast format-bytes32-string "research-access"` →
  `0x72657365617263682d6163636573730000000000000000000000000000000000`), NOT `keccak256`. Use that
  exact value for `resources()`, `setResourceActive()`, `purchase()`, etc.
  Verified live on-chain 2026-06-13: all params stored correctly, gate unpaused, sink=Treasury → Ledger.

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
- [x] **AccessGate (spend-to-access) MILESTONE COMPLETE — 2026-06-14, tag `accessgate-v1`.** Fully built and
      exercised live on mainnet: `LSLAccessGate` deployed + both access models configured (`research-access`
      Subscription + `dataset-download` PerUse) + operator authorized/funded; live buy→consume→sink-routing
      verified. Off-chain **SIWE-secured reverse-proxy gatekeeper** (`scripts/gatekeeper.mjs`) with stateless
      HMAC sessions, `/nonce` rate-limiting, `/health`, ops CLI (`scripts/gate.sh`), and client
      (`scripts/gate-login.mjs`). **Deployment kit**: `Dockerfile`, validating launcher
      (`scripts/gatekeeper-run.sh`), Cloud Run config (`deploy/`), keyless CI→GHCR/Artifact Registry
      (Node 24-ready). Full breakdown in git history + the On-chain facts above. **What remains is ops +
      business decisions only — no code**: stand up a host + TLS, point `gate-upstreams.json` at the real service,
      finalize resource pricing, and the legal/tax track for token distribution.

## NOT done / current frontier ⏳

**Open — the only remaining work (both non-code, gated on decisions):**
- [ ] **Distribution to EXTERNAL recipients — not started.** All 1,000,000 LSL is on own wallets
      (index 0: 995,070, index 1: 4,930); nothing sold or traded to third parties. `distribution.json` is
      the placeholder. Step-by-step: **`DISTRIBUTION-RUNBOOK.md`**.
- [ ] **Legal/tax engagement — open.** Clear the distribution model with securities counsel + a
      crypto-literate tax pro (`LEGAL-TAX-CHECKLIST.md`) before moving any tokens.

**Done — condensed (full detail in git history, `broadcast/`, Etherscan, and `~/lsl-legal/…csv`):**
- [x] **Distribution mechanics proven live on mainnet** — 1 LSL + 100 LSL self-test rehearsals (swept back),
      then the first real **5,000 LSL `LSLDisperse` batch** to index 1 (NOT swept — index 1 holds 5,000,
      index 0 holds 995,000). Full sign→verify→send→confirm flow validated; supply always conserved.
- [x] **Custody (2026-06-06):** supply stays on the single Ledger key — no multisig. The offline seed
      backup is the single point of failure.
- [x] **AccessGate milestone COMPLETE** (tag `accessgate-v1`; see DONE ✅) — Sepolia rehearsal → mainnet
      deploy/verify → both resources (`research-access` Subscription, `dataset-download` PerUse) + operator
      `0x7a758A45972453D4E37A495C3244Ce9D83CC4518` → live buy/consume/sink-routing → SIWE reverse-proxy
      gatekeeper (stateless sessions, rate-limit, `/health`) → deployment kit (`Dockerfile`, launcher,
      Cloud Run, Node 24-ready CI). Key addresses in **On-chain facts** above.
- [x] **Recurring ops gotcha:** connect ONE Ledger only (two devices → `cast` derived the WRONG wallet
      `0x2C9b…`); on ChromeOS/Crostini share the USB + `sudo chown $USER /dev/bus/usb/<BUS>/<DEV>`; ALWAYS
      verify `cast wallet address` reads `0x7C9e…Bc1a` BEFORE signing.

## >>> NEXT ACTION <<<
All contract code + tooling is DONE and exercised live on mainnet — token, LSLDisperse (first 5,000 LSL
batch run), and LSLAccessGate (both resources, operator, SIWE-secured reverse-proxy gatekeeper, real
endpoint wired). Two open tracks remain, both gated on decisions/ops, NOT code:

### A. Token distribution to EXTERNAL recipients — gated on legal/tax
- Entity is formed: **Jensen Communications LLC** (DE, single-member) d/b/a "Living Science Lab"; the LLC
  holds the 1,000,000 LSL via the single Ledger key (index 0). Disperse mechanics are proven live (the
  5,000 LSL → index 1 own-wallet run). What's missing is real verified recipients + sign-off.
- Get **securities counsel + a crypto-literate tax pro** to clear the distribution MODEL (sale vs. reward,
  registration/exemption) before moving any LSL to third parties.
- When cleared: follow **`DISTRIBUTION-RUNBOOK.md`** — the full step-by-step (intake + proof-of-control →
  build `distribution.json` → Ledger readiness → dry-run `scripts/disperse.sh mainnet` → broadcast →
  verify + record FMV/tx for tax). Preserve every tx + date + FMV (`broadcast/` is the audit trail; the
  first LSLDisperse run is already committed there).

### B. AccessGate productionization — gated on ops, NOT code
The gate is live and the gatekeeper is built, SIWE-secured, and verified — but it is a reference template
currently wired to an Alchemy demo upstream. To monetize for real:
1. **Wire the real gated service**: edit `gate-upstreams.json` (gitignored) to point each resource at the
   actual endpoint (URL + headers/body). Today `research-access` → Alchemy `eth_blockNumber` (demo only).
2. **Finalize catalog + pricing**: current resources are placeholders (research-access 50 LSL/30d,
   dataset-download 10 LSL/use) — adjust via `setResource` (Ledger-signed) once real prices are decided.
3. **Host it — deployment kit is DONE** (see `DEPLOY-GATEKEEPER.md`): stateless HMAC session tokens
   (`GATE_SESSION_SECRET`, generated into `.env`), `/nonce` rate-limiting (`NONCE_RATE_MAX`), a `/health`
   probe, container-friendly config (merges `.env` + env vars), `Dockerfile` (bundles `cast`), and a
   validating launcher `scripts/gatekeeper-run.sh` (refuses to start in prod without a real `GATE_DOMAIN` +
   secret). All tested. **What's left is pure ops, no code**: stand up a host/Cloud Run, set `GATE_DOMAIN`
   to the real host, terminate **TLS** in front (LB or Caddy), and for multi-node share the single-use
   nonce store (e.g. Redis). Proof-of-control already enforced via SIWE.
   - **Turnkey GCP deploy added**: `deploy/cloudrun-deploy.sh` (build→Artifact Registry via Cloud Build,
     push local secrets→Secret Manager, least-priv runtime SA, `gcloud run deploy` with env + mounted
     secrets, pinned to 1 instance) and a declarative `deploy/cloudrun-gatekeeper.yaml`. Gatekeeper gained
     a `GATE_UPSTREAMS_FILE` override (for mounted-secret upstream config) and a `.dockerignore`. Run:
     `PROJECT_ID=… GATE_DOMAIN=… deploy/cloudrun-deploy.sh`, then map the domain for TLS. NOT run here
     (needs your GCP project/auth) — set the real `gate-upstreams.json` first.
   - **Keyless CI → Artifact Registry**: the image workflow now ALSO pushes to GCP Artifact Registry via
     Workload Identity Federation (no SA keys) when configured. One-time setup `deploy/setup-wif.sh`
     (creates pool/provider/pusher-SA scoped to this repo, prints the repo Variables to set:
     `GCP_WIF_PROVIDER`/`GCP_DEPLOY_SA`/`GCP_PROJECT`/`GCP_AR_REGION`/`GCP_AR_REPO`). Until those vars are
     set, CI pushes GHCR only (AR steps skipped). Image still verified building+pushing green in CI.
   - **CI is Node 24-ready (2026-06-14)**: ahead of GitHub's 2026-06-16 forced Node 20→24 migration, the
     image workflow's actions were bumped to node24 majors (`setup-buildx-action@v4`, `login-action@v4`,
     `metadata-action@v6`, `build-push-action@v7`, `google-github-actions/auth@v3`; `checkout@v6` already
     node24). Verified: the post-bump run is green with the Node 20 deprecation annotation gone. `test.yml`
     (foundry CI) was already clean — no change needed.
4. Operator hot key `0x7a758A45972453D4E37A495C3244Ce9D83CC4518` is funded 0.001 ETH; top up as
   `consume()` volume grows.

### Housekeeping
- **index 0 ETH is ~0.0034** after the AccessGate session — top up before the next Ledger-signed work.

## OPEN QUESTIONS for the user
- ~~Is the Ledger 24-word seed phrase backed up offline?~~ **CONFIRMED: yes, backed up offline (2026-06-06).**
- ~~Supply stays on the single Ledger address, or move to a multisig (Safe)?~~ **DECIDED: single Ledger key (2026-06-06).**
- ~~Issuing entity: still to be decided.~~ **DECIDED (2026-06-13): Jensen Communications LLC** (DE,
  single-member) d/b/a "Living Science Lab" (DBA registered); the LLC owns the 1,000,000 LSL via capital
  contribution. Securities/tax review of the distribution *model* is still open (see NEXT ACTION track A).

## Tooling locations (this machine)
- Foundry (forge/cast/anvil): `~/.config/.foundry/bin/` (add to PATH)
- gcloud: `~/google-cloud-sdk/bin/gcloud`
- Slither: `~/.slither-venv/bin/slither`
- Node 22, npm, git, gh 2.93 all installed
