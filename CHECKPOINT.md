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
      (Node 24-ready). See the frontier section for the full breakdown. **What remains is ops + business
      decisions only — no code**: stand up a host + TLS, point `gate-upstreams.json` at the real service,
      finalize resource pricing, and the legal/tax track for token distribution.

## NOT done / current frontier ⏳
- [x] **Distribution pipeline proven end-to-end on mainnet (2026-06-13, live self-test)** — used the
      Ledger's **index-1** address (`m/44'/60'/0'/0/1` = `0x0a78378b424a19DC752bB99d2802521E8DD0C590`)
      as a stand-in recipient and ran the full real flow: signed the control-of-address proof from index 1,
      `cast wallet verify` ✅ (plus a negative control against index 0 that correctly REJECTED), then sent a
      **1 LSL** test transfer from index 0 — tx
      `0x34cdd7b695817aafa9188ad597bdfaa630cd8a432d490c910eb64293f928910b` (block 25311983), recipient
      balance confirmed 1 LSL, totalSupply unchanged. The mechanics (derive → sign → verify → send → confirm)
      are validated; real distribution now only needs real verified recipients. The 1 LSL test was then
      **swept back to index 0** (fund-gas tx `0xbb9e5eda…6b317f`, sweep tx `0xd96b55db…85b1cb0d9`), so the
      full 1,000,000 supply is reconsolidated on index 0; a ~0.0000262 ETH gas dust remains on index 1
      (same seed, recoverable).
- [x] **Full 100 LSL real-flow rehearsal on mainnet (2026-06-13)** — repeated the whole recipient pipeline
      at production amount against index 1 (`0x0a78…C590`): fresh control-of-address signature
      `cast wallet verify` ✅, **1 LSL** test transfer (tx `0xe91cc838…926d0f81`) confirmed received, then
      **99 LSL** balance (tx `0x503f8bd2…7506ff1d`) → index 1 held 100 LSL, supply conserved. Then **swept
      all 100 LSL back** to index 0 (tx `0x3c4960ad…057e78cd`; index 1 had enough leftover ETH dust to pay
      gas, so no funding tx needed). Supply fully reconsolidated at 1,000,000 on index 0. Logged in
      `~/lsl-legal/LSL-contributor-master-tracking.csv` (marked Internal-Test). Confirms the
      sign→verify→test→balance→sweep flow works at real amounts; live distribution now only needs a real
      verified recipient. Outreach draft template prepared in Gmail (100 LSL).
- [x] **First live LSLDisperse batch on mainnet (2026-06-14)** — exercised the deployed disperse helper
      end-to-end at production scale: **5,000 LSL** sent from index 0 → index 1 (`0x0a78…C590`) in one
      batch. approve tx `0x7af500d13539b0463897aba9e6c6c6a595b11667a3b4cf9ed1051cd6dc278824` (block
      25318476); disperse tx `0x63e71d7c4822e5f3468274f6445f2c672d2e044d83c4055546d754f28b09415d` (block
      25318486); allowance returned to 0. **NOT swept back** — index 1 (same seed) now holds 5,000 LSL,
      index 0 holds 995,000; total supply unchanged. Own-wallet transfer, NOT a contributor distribution;
      logged in `~/lsl-legal/LSL-contributor-master-tracking.csv` (bucket `Own-wallet`). Ledger/Crostini fix
      that unblocked it: share USB into the container + `sudo chown $USER /dev/bus/usb/<BUS>/<DEV>` (reverts
      on re-plug/lock).
- [ ] **Distribution to real (external) recipients not started** — `distribution.json` is back to the
      placeholder template. The bulk of supply (995,000 LSL) sits on the single Ledger index 0; nothing
      sold or traded to third parties.
- [ ] **Legal/tax engagement open** — per `LEGAL-TAX-CHECKLIST.md`, decide distribution model
      + entity + counsel review *before* moving any tokens.
- [x] **Custody decided (2026-06-06): supply stays on the single Ledger key** — no Safe/multisig
      migration. Makes the offline seed-phrase backup the critical single point of failure.
- [x] **LSLDisperse verified on Etherscan (2026-06-12)** — done with a fresh V2 API key (the old V1
      key was rejected by Etherscan's V2 API; `.env` now holds a working V2 key).
- [x] **LSLAccessGate FULL Sepolia rehearsal passed (2026-06-13)** — deployed + Etherscan-verified at
      `0x4b33B297A8C9AdFca97D9aEF980102D4ef9613F3` (Sepolia), then exercised end-to-end per
      `ACCESSGATE-SEPOLIA-REHEARSAL.md`: setResource (PerUse + Subscription), setOperator, purchase
      (both models), consume (credits decrement + access revokes at 0), BOTH sinks (Treasury routing +
      Burn → totalSupply dropped 3 LSL), pause/unpause, setResourceActive. Not exercised: purchaseWithPermit
      (used plain approve+purchase fallback) and the non-operator consume revert (covered by unit tests).
- [x] **AccessGate DEPLOYED + Etherscan-verified on mainnet (2026-06-13)** at
      `0x14c129b8D22491a2cCE9Be36137eC8d9B9b31Db5`. Launch params: **SINK=0 (Treasury)**, treasury =
      owner = Ledger `0x7C9e…Bc1a`. Deploy tx
      `0xeeb75d87029f94664ecf0828f69d290343b0571594d69695026b496e1ee0d00f`, block 25306831, 1,326,002 gas.
      Securities counsel cleared the spend-to-access model for mainnet (per user 2026-06-13). Address in
      `.env` as `LSL_ACCESS_GATE_ADDRESS`. First resource configured 2026-06-13: **`research-access`** =
      Subscription, 50 LSL / 30 days, active. Add/update more via `setResource`; `sink`/`treasury` are
      runtime-changeable via `setSink`.
- [x] **AccessGate fully set up + exercised live on mainnet (2026-06-14)** — both access models now
      configured and proven end-to-end:
      - Second resource added: **`dataset-download`** = **PerUse, 10 LSL/use**, active
        (`setResource` tx `0xdb4fb3d75bdaf1a123995f865bf1b95e4c10895d0ed37bd0809f3ef1702d44d8`).
      - **Operator authorized + funded**: hot key **`0x7a758A45972453D4E37A495C3244Ce9D83CC4518`**
        (`setOperator` tx `0xa3b86c3a982d4d6f59be9ba6f8ec5a267f939060709dc38e5be4e9aebc56cdf9`; funded
        0.001 ETH for `consume` gas). Encrypted keystore in `.secrets/` (gitignored); pw + address in
        `.env` as `OPERATOR_*`. Blast radius is tiny — `consume()` can only decrement credits, never move
        funds/sink/treasury.
      - **Live test from index 1** (`0x0a78…C590`, the 5,000-LSL buyer): bought research-access (1 period,
        50 LSL) → `hasAccess=true`; bought dataset-download (2 credits, 20 LSL); operator consumed credits
        down to 0 (incl. one via the gatekeeper `/serve` path). Sink routing confirmed: the **70 LSL flowed
        buyer → gate → treasury (index 0)**, so index 0 = 995,070 LSL, index 1 = 4,930 LSL, gate holds 0
        (no custody). totalSupply unchanged.
      - **Off-chain tooling added**: `scripts/gate.sh` (ops CLI: status/resource/quote/access/buy/consume/id,
        string-id encoding via `cast format-bytes32-string`, NOT keccak256) and `scripts/gatekeeper.mjs`
        (zero-dep reference middleware fronting the real service: Subscription serves free, PerUse redeems a
        credit via the operator; **placeholder payload — wire your real endpoint in**).
      - **SIWE proof-of-control added to the gatekeeper (2026-06-14)** — closes the spoof hole where anyone
        could `/serve?user=<victim>` and spend/ride their access. Flow: `GET /nonce` (single-use, 10-min TTL)
        → `POST /login {message,signature}` verifies the EIP-4361 message via `cast wallet verify` (+ domain
        binding, nonce + expiry checks) and issues a 1-h session token → `POST /serve` requires a Bearer token
        and derives the user from the SESSION, never a param. `GET /check` stays public (read-only on-chain
        state). Reference client + CLI: `scripts/gate-login.mjs` (`--key 0x..` or `--ledger N`). Tested green:
        valid login 200; no-token / replayed-nonce / tampered-sig / wrong-domain all 401; session-with-no-access
        402. Also verified LIVE with the real Ledger: index 1 signed the SIWE message on-device → session →
        `POST /serve research-access` returned 200 (active subscription, no credit burned). NOTE:
        nonces/sessions are in-memory (fine for a template; persist them for production).
      - **Reverse-proxy wiring added (2026-06-14)** — `/serve` now forwards an authorized request to a
        per-resource upstream from **`gate-upstreams.json`** (gitignored; template `gate-upstreams.example.json`),
        injecting the upstream's own auth headers + `X-LSL-User`/`X-LSL-Resource`, and relays the response
        verbatim (binary-safe). For PerUse it **burns the credit only AFTER the upstream returns <400**, so a
        failing upstream never costs a credit (upstream error → 502, no consume). Upstream URL comes from
        trusted server config, not user input (no SSRF). Verified end-to-end on a local **anvil mainnet fork**
        (no Ledger): software buyer purchased research-access on the fork → SIWE login → `/serve` returned the
        upstream's payload with `delivered_to`/`for_resource`/`upstream_auth_seen` all correct. **To go live:
        `cp gate-upstreams.example.json gate-upstreams.json`, set the real URL(s) + API key(s).**
      - **`deliver()` extended with optional `body` support + wired to a real endpoint (2026-06-14)** — upstream
        config now accepts a fixed request `body` (string or JSON object) for POST/JSON-RPC upstreams.
        `gate-upstreams.json` (gitignored — holds the Alchemy key) wires **`research-access` → Alchemy mainnet
        RPC** (`POST` JSON-RPC `eth_blockNumber`). Verified end-to-end on an anvil fork: SIWE-authed software
        buyer → `/serve research-access` returned the SAME live response as a direct curl
        (`{"jsonrpc":"2.0","id":1,"result":"0x182582e"}`), confirming the gatekeeper forwards method+headers+body
        and relays the real upstream response. Swap the `url`/`body` in `gate-upstreams.json` to point at the
        actual gated service.
      - **Ledger/Crostini gotcha hit again**: had TWO Ledgers plugged in → `cast` derived the WRONG wallet
        (`0x2C9b…`); fix was unplug the extra device + re-`chown` the re-enumerated `/dev/bus/usb` node, then
        VERIFY `cast wallet address` reads `0x7C9e…Bc1a` BEFORE signing. Always verify the address first.

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
- When cleared: `cp distribution.example.json distribution.json`, fill real recipients + whole-LSL amounts,
  then **dry-run first** with the preferred single-batch path `scripts/disperse.sh mainnet` (simulates +
  previews, then asks before the 2 Ledger-signed txs). Preserve every tx + date + FMV for tax
  (`broadcast/` is the audit trail; the LSLDisperse run is already committed there).

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
