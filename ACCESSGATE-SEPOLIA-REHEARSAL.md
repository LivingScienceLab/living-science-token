# LSLAccessGate — Sepolia Rehearsal Plan

_Run this end-to-end on Sepolia BEFORE any mainnet deploy of `LSLAccessGate`._
_Gated upstream on the legal/tax sign-off in `LEGAL-TAX-CHECKLIST.md` — the spend-to-access /
treasury-revenue model is the regulatory decision; this doc is the technical gate._

The point of a rehearsal is to validate, against a live chain, the things unit tests can't fully
cover: the **constructor args you actually pass**, the **Etherscan verification flow**, and the
**purchase → redeem → sink → pause** behavior with a real ERC-20 and real signatures. `LSLDisperse`
could be deployed blind because it's trivial and stateless; `LSLAccessGate` is owner-administered,
stateful, and immutable once live — so it gets the full dry run.

All amounts are LSL in **wei** (18 decimals) unless noted. Ledger-signed steps are marked **🔑**.

---

## Phase 0 — Pre-flight

- [ ] **Legal/tax sign-off recorded** for the spend-to-access model (`LEGAL-TAX-CHECKLIST.md`). Do not proceed without it.
- [ ] `set -a; source .env; set +a` — loads `SEPOLIA_RPC_URL`, `LEDGER_SENDER`, `ETHERSCAN_API_KEY` (must be the working **V2** key).
- [ ] Ledger ready: unlocked, Ethereum app open, blind signing ON. On Crostini, chown the USB node first (see `CLAUDE.md` Ledger gotchas).
- [ ] **Sepolia ETH** for gas on `$LEDGER_SENDER` (use a faucet if low):
      `cast balance "$LEDGER_SENDER" --rpc-url "$SEPOLIA_RPC_URL"`
- [ ] **Sepolia LSL** exists at the deterministic address `0xe1Eb0f66a15b80f64CA252fbe0CA3087F74A9B08`
      (deployed in the original Sepolia dry run) and `$LEDGER_SENDER` holds a balance to spend:
      `cast call 0xe1Eb0f66a15b80f64CA252fbe0CA3087F74A9B08 "balanceOf(address)(uint256)" "$LEDGER_SENDER" --rpc-url "$SEPOLIA_RPC_URL"`
- [ ] **(Recommended)** a *second* EOA to act as the "user" so owner≠buyer and access-control is tested for real. If you only have the Ledger, you can self-test (owner buys), but it's a weaker check. Set `USER_ADDR` to whichever you use.

```bash
export GATE=          # filled in Phase 1
export LSL=0xe1Eb0f66a15b80f64CA252fbe0CA3087F74A9B08
export USER_ADDR=     # second EOA, or "$LEDGER_SENDER" for a self-test
```

---

## Phase 1 — Deploy + verify the gate on Sepolia 🔑

Start with the **Treasury** sink (`SINK=0`), treasury = your Ledger, so you can watch LSL arrive.

- [ ] **Dry run** (no signature):
```bash
SINK=0 TREASURY="$LEDGER_SENDER" \
forge script script/DeployAccessGate.s.sol:DeployAccessGate \
  --rpc-url sepolia --sender "$LEDGER_SENDER" -vvvv
```
- [ ] **Broadcast + verify** 🔑:
```bash
SINK=0 TREASURY="$LEDGER_SENDER" \
forge script script/DeployAccessGate.s.sol:DeployAccessGate \
  --rpc-url sepolia --ledger --sender "$LEDGER_SENDER" --broadcast --verify -vvvv
```
- [ ] Record the deployed address → `export GATE=0x...`
- [ ] Confirm it shows **verified** on Sepolia Etherscan (this rehearses the exact verify path mainnet will use).
- [ ] Sanity-read the constructor wiring:
```bash
cast call "$GATE" "token()(address)"    --rpc-url "$SEPOLIA_RPC_URL"   # == $LSL
cast call "$GATE" "sink()(uint8)"       --rpc-url "$SEPOLIA_RPC_URL"   # == 0 (Treasury)
cast call "$GATE" "treasury()(address)" --rpc-url "$SEPOLIA_RPC_URL"   # == $LEDGER_SENDER
cast call "$GATE" "owner()(address)"    --rpc-url "$SEPOLIA_RPC_URL"   # == $LEDGER_SENDER
```

---

## Phase 2 — Owner configuration 🔑

Define one resource of **each** access model so both code paths get exercised.

```bash
# Human-readable resource ids
export PERUSE_ID=$(cast format-bytes32-string "credits")
export SUB_ID=$(cast format-bytes32-string "monthly")
```

- [ ] **PerUse** resource: model=0, price=1 LSL/use, duration ignored, active=true 🔑
```bash
cast send "$GATE" "setResource(bytes32,uint8,uint128,uint64,bool)" \
  "$PERUSE_ID" 0 1000000000000000000 0 true \
  --ledger --rpc-url "$SEPOLIA_RPC_URL"
```
- [ ] **Subscription** resource: model=1, price=5 LSL/period, duration=30 days, active=true 🔑
```bash
cast send "$GATE" "setResource(bytes32,uint8,uint128,uint64,bool)" \
  "$SUB_ID" 1 5000000000000000000 2592000 true \
  --ledger --rpc-url "$SEPOLIA_RPC_URL"
```
- [ ] **Operator** (needed to redeem PerUse credits) — authorize your Ledger as operator 🔑
```bash
cast send "$GATE" "setOperator(address,bool)" "$LEDGER_SENDER" true \
  --ledger --rpc-url "$SEPOLIA_RPC_URL"
```
- [ ] Read back: `quote` should reflect price × quantity
```bash
cast call "$GATE" "quote(bytes32,uint256)(uint256)" "$PERUSE_ID" 3 --rpc-url "$SEPOLIA_RPC_URL"  # 3 LSL
cast call "$GATE" "quote(bytes32,uint256)(uint256)" "$SUB_ID" 1 --rpc-url "$SEPOLIA_RPC_URL"     # 5 LSL
```

---

## Phase 3 — User purchase flows 🔑

If `USER_ADDR` is a separate EOA, run these signed by *that* key (swap `--ledger`/`--sender`
or use a keystore). For a self-test, the Ledger is the buyer.

**A. PerUse via plain approve + purchase**
- [ ] Approve the gate to pull the cost (3 LSL for 3 credits) 🔑
```bash
cast send "$LSL" "approve(address,uint256)" "$GATE" 3000000000000000000 --ledger --rpc-url "$SEPOLIA_RPC_URL"
```
- [ ] Purchase 3 credits 🔑
```bash
cast send "$GATE" "purchase(bytes32,uint256)" "$PERUSE_ID" 3 --ledger --rpc-url "$SEPOLIA_RPC_URL"
```
- [ ] Verify access granted: `hasAccess` true, and the `Purchased` event fired.
```bash
cast call "$GATE" "hasAccess(address,bytes32)(bool)" "$USER_ADDR" "$PERUSE_ID" --rpc-url "$SEPOLIA_RPC_URL"
```

**B. Subscription via `purchaseWithPermit` (gasless approve — exercises LSL's EIP-2612 path)**
- [ ] Build an EIP-2612 permit signature for `(owner=buyer, spender=GATE, value=5 LSL, deadline)` and call.
      Signature is `purchaseWithPermit(id, quantity, value, deadline, v, r, s)` — `value` is the
      permit allowance (use `quote(SUB_ID, 1)` = 5 LSL):
```bash
cast send "$GATE" "purchaseWithPermit(bytes32,uint256,uint256,uint256,uint8,bytes32,bytes32)" \
  "$SUB_ID" 1 5000000000000000000 <deadline> <v> <r> <s> --ledger --rpc-url "$SEPOLIA_RPC_URL"
```
  _(Permit signing is the fiddliest step; if you'd rather, test Subscription with the plain
  approve+purchase path too and treat permit as a separate, optional check.)_
- [ ] Verify `hasAccess(USER_ADDR, SUB_ID)` is true and note the expiry timestamp.

---

## Phase 4 — Redemption + access semantics

- [ ] **Redeem a PerUse credit** as operator 🔑 — consume 1 of the 3 credits:
```bash
cast send "$GATE" "consume(address,bytes32,uint256)" "$USER_ADDR" "$PERUSE_ID" 1 \
  --ledger --rpc-url "$SEPOLIA_RPC_URL"
```
- [ ] Confirm the `Consumed` event shows `remaining = 2`, and `hasAccess` is still true (credits left).
- [ ] Consume the remaining 2; confirm `hasAccess(PERUSE_ID)` flips to **false** at zero credits.
- [ ] Confirm a non-operator calling `consume` **reverts** (access control negative test).

---

## Phase 5 — Sink behavior

**Treasury sink (current):**
- [ ] Confirm spent LSL landed in `treasury` ($LEDGER_SENDER) — check the `Collected` event and the treasury balance delta across the purchases.

**Switch to Burn and re-test 🔑:**
- [ ] `setSink(1, 0x0000000000000000000000000000000000000000)` (Burn; treasury ignored):
```bash
cast send "$GATE" "setSink(uint8,address)" 1 0x0000000000000000000000000000000000000000 \
  --ledger --rpc-url "$SEPOLIA_RPC_URL"
```
- [ ] Note LSL `totalSupply` before, make one more purchase, confirm `Burned` event fired and
      `totalSupply` **decreased** by the cost.
```bash
cast call "$LSL" "totalSupply()(uint256)" --rpc-url "$SEPOLIA_RPC_URL"
```

---

## Phase 6 — Safety controls 🔑

- [ ] **Pause**: `cast send "$GATE" "pause()" --ledger --rpc-url "$SEPOLIA_RPC_URL"`
- [ ] Confirm `purchase` now **reverts** (whenNotPaused) while `consume`/reads still behave as designed.
- [ ] **Unpause**: `cast send "$GATE" "unpause()" --ledger ...`; confirm `purchase` works again.
- [ ] **setResourceActive(id, false)** on a resource → confirm purchase of that id reverts; reactivate.
- [ ] Confirm owner-only functions **revert for non-owner** callers (access control).

---

## Exit criteria → cleared for mainnet

Mainnet deploy of `LSLAccessGate` is justified only when ALL of these hold:
- [ ] Legal/tax sign-off on the spend-to-access model is recorded.
- [ ] Sepolia gate deployed **and Etherscan-verified** with no surprises in constructor wiring.
- [ ] Both access models (PerUse credits + Subscription expiry) purchased and access-checked.
- [ ] Redemption (`consume`) decrements credits and revokes access at zero; non-operator blocked.
- [ ] Both sinks proven: Treasury received LSL; Burn reduced `totalSupply`.
- [ ] `pause`/`unpause` and `setResourceActive` gate purchases as expected; owner-only access enforced.
- [ ] Final mainnet constructor params decided: **sink (Treasury vs Burn)** and **treasury address**
      (the sink is runtime-toggleable via `setSink`, but pick the launch default deliberately).

Then deploy to mainnet with the SAME command as Phase 1, swapping `--rpc-url sepolia` → `mainnet`,
and record the address + tx in `CHECKPOINT.md` (mirroring the LSLDisperse entry).

---

_Note on scope: there is no pre-built "exercise" script for the gate — these are `cast` calls by
design, since a rehearsal is meant to poke the live contract by hand. If this becomes routine,
the interaction steps could be scripted later, but hand-driving is the right altitude for a
one-time, high-stakes rehearsal._
