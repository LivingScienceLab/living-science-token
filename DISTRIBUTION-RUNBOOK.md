# LSL Distribution Runbook

How to distribute Living Science Token (LSL) to real recipients once legal/tax has signed off.
Grounded in the repo tooling (`scripts/disperse.sh`, `distribution.json`, the contributor tracking
CSV) and the operational gotchas hit during testing.

> **Gate:** Do not start Phase 1+ until **Phase 0** is cleared. Distribution is blocked on decisions,
> not code — see `LEGAL-TAX-CHECKLIST.md` and `CHECKPOINT.md` › NEXT ACTION › Track A.

**On-chain facts**
- Token: `0xe1Eb0f66a15b80f64CA252fbe0CA3087F74A9B08` (immutable, 1,000,000 supply)
- Issuer / source: Jensen Communications LLC via Ledger **index 0** `0x7C9eF832417e63F805ccaAbD131741aceEB5Bc1a`
- Batch helper (preferred): LSLDisperse `0x2d6fEC5f0d3611Ec9BFe7b633bD180B49d17Fcdd`

---

## Phase 0 — Legal/tax sign-off (the gate)
Before any token moves, obtain from securities counsel + a crypto-literate tax pro:
- **Distribution model** cleared: sale vs. reward/compensation vs. airdrop; applicable exemption
  (e.g. Reg D / Reg S), any transfer restrictions, and whether **KYC/AML** is required per recipient.
- **Token agreements**: whether each recipient must sign terms before receiving.
- **Vesting decision** ⚠️: the LSL contract has **no vesting/lockup**. If vesting is required, either
  (a) hold and release manually over time, or (b) deploy a separate vesting contract (NOT built). This
  changes the mechanics — decide here.
- **Tax treatment + FMV method**: how the LLC's disposal and the recipient's receipt are treated, and
  how USD fair-market value is set at each transfer for records.

## Phase 1 — Per-recipient intake (before tokens move)
For each recipient, recorded in `~/lsl-legal/LSL-contributor-master-tracking.csv`:
1. Collect their **receiving address**.
2. **Proof-of-control** (critical — transfers are irreversible): recipient signs a control message;
   verify with `cast wallet verify --address <theirs> "<msg>" <sig>`, plus a negative control against a
   wrong address. Mark `proof_sig_verified=yes`.
3. **KYC** if counsel requires (`kyc_done`).
4. **Signed agreement** if required.
5. Record: name, email, `address_checksummed`, bucket, `amount_lsl`, vesting, date.

## Phase 2 — Build the batch file
1. `cp distribution.example.json distribution.json` (gitignored).
2. Fill `recipients[]` (checksummed — `cast to-check-sum-address 0x...`) and `amountsTokens[]`
   (**whole LSL**, not wei; arrays equal length, positionally aligned).
3. Confirm **total ≤ index 0 balance**. The script also rejects zero / self / duplicate recipients.
4. **Top up index 0 ETH** for gas if low.

## Phase 3 — Ledger readiness (gotchas that bit us)
1. **Only one Ledger connected** (two devices → `cast` derived the WRONG wallet).
2. Unlocked, **Ethereum app open, blind signing ON**.
3. On ChromeOS/Crostini: share USB into Linux, then `sudo chown $USER /dev/bus/usb/<BUS>/<DEV>`
   (reverts on re-plug/lock).
4. **Verify before signing**:
   `cast wallet address --ledger --mnemonic-derivation-path "m/44'/60'/0'/0/0"` must return
   **`0x7C9eF832417e63F805ccaAbD131741aceEB5Bc1a`**.

## Phase 4 — Dry run (no signature)
```
scripts/disperse.sh mainnet
```
Simulates approve + disperse against live state; prints per-recipient preview, total, and remaining.
Review every line. (`LSL_DISPERSE` is already aliased in `.env`.)

## Phase 5 — Broadcast (Ledger-signed)
At the prompt type `yes`, then confirm **two** transactions on the device: `approve`, then `disperse`
(`--slow` waits for the approve to mine first). Two tx hashes print.
- **Safety practice**: make the *first* real batch a **single small recipient**, confirm it landed,
  then scale up.

## Phase 6 — Verify + record (tax/audit)
1. Confirm each recipient's on-chain balance; index 0 dropped by the total; `totalSupply` unchanged.
2. Per recipient, record `final_tx_hash`, `date`, and **USD FMV** in the tracking CSV.
3. Commit the `broadcast/DisperseBatch.s.sol/1/` artifacts (the audit trail), as done for the first
   5,000 LSL run.
4. Provide recipients any documentation they need for their own taxes.

## Path choice
- **`scripts/disperse.sh`** — one atomic batch, 2 Ledger sigs total regardless of recipient count.
  Preferred for any multi-recipient list.
- **`scripts/distribute.sh`** — sequential `transfer` (one Ledger sig per recipient). Fine for one-offs.
