# Security Review — Living Science Token contracts

**Scope:** `src/LivingScienceToken.sol`, `src/LSLDisperse.sol`, `src/LSLAccessGate.sol`
**Date:** 2026-06-13
**Reviewer:** informal internal review (Claude, in-session). **NOT a professional third-party audit.**
**Toolchain context:** Solidity 0.8.24, OpenZeppelin v5, Foundry. 54 unit/fuzz tests pass; Slither reports 0 findings; a prior independent subagent review was clean.

> This is a code/logic review for internal records. For anything carrying significant value to third
> parties, commission a professional audit. The LSL token and LSLDisperse are **immutable** (deployed,
> non-upgradeable) — findings on them are informational. LSLAccessGate is **owner-configurable**, so its
> notes are actionable operationally and/or in a future redeploy.

## Verdict

**No critical or high-severity issues. No fund-loss vulnerabilities.** The token and disperse helper
are minimal and correct. The access gate is well-guarded (`Ownable` / `Pausable` / `ReentrancyGuard`,
`SafeERC20`). Remaining items are low / informational / centralization-trust.

---

## LivingScienceToken.sol — Clean

Fixed-supply OZ `ERC20 + ERC20Burnable + ERC20Permit`. Supply minted once in the constructor, zero-address
guard, no mint function, no owner/admin, checked arithmetic (0.8.24). No findings. (Immutable.)

## LSLDisperse.sol — Clean for purpose

Stateless, custody-free, atomic batch transfer via `transferFrom`. No reentrancy surface (no state; bounded
by the caller's own allowance). Notes only:

- **[Info]** Uses raw `transferFrom` + boolean-return check (not `SafeERC20`). Correct for LSL (OZ returns
  `bool`); a non-compliant no-return token (e.g. USDT) would not work despite the "any standard ERC-20"
  comment. Acceptable — it is for LSL.
- **[Info]** No dedup / zero-amount / self-recipient checks in the contract; delegated to the
  `DisperseBatch.s.sol` script (which does validate). Acceptable.

## LSLAccessGate.sol — Solid; low / centralization notes

| # | Severity | Finding | Recommendation |
|---|----------|---------|----------------|
| 1 | Low | `setResourceActive(id, true)` on an **unconfigured id** silently creates a **price-0, active PerUse** resource → anyone could mint unlimited free credits for it. | Owner footgun. Only call `setResourceActive` on resources already created via `setResource`. Future version: require the resource to exist (see patch below). |
| 2 | Trust | Authorized **operators can `consume` (zero out) any user's PerUse credits** arbitrarily — by design (the off-chain backend redeems as it serves). A compromised operator key can grief users out of paid access (cannot steal LSL). | Use a minimal-privilege, well-secured backend signer as operator; rotate/revoke promptly via `setOperator`. Treat the operator key as security-sensitive. |
| 3 | Centralization | Owner controls prices, sink, treasury, operators, and pause. Cannot mint or seize spent funds beyond what a user spends, but controls future pricing/destination. | Acceptable while owner = single Ledger. If users need price-stability guarantees, migrate ownership to a multisig/timelock. |
| 4 | Info | **No token-rescue function** — LSL (or any token) sent *directly* to the gate (outside `purchase`) is permanently stuck. | Accepted trade-off for trustlessness. Be aware; don't send tokens directly to the gate. |
| 5 | Info | Subscription expiry delta `uint64(uint256(duration) * quantity)` truncates on absurd `quantity` — but `cost` exceeds total supply long before that, so `_collect` reverts first. **Not reachable.** | None. |
| 6 | Info | `_collect` (external calls) runs **before** the credit/expiry state update in `_purchase` (checks-effects-interactions inversion). Safe only because of `nonReentrant` + non-callback token (LSL). | Fine as-is. If ever reused with a callback-capable token, move effects before interactions. |
| 7 | Info | `pause()` blocks `purchase` but **not** `consume` (existing credits remain redeemable while paused); zero-price resources are allowed (free tier). | Appear intentional — confirm they match intent. |

### Owner / operator powers — explicit trust model
- **Owner CAN:** set/deactivate resources & prices, change sink (Treasury↔Burn) and treasury address,
  add/remove operators, pause/unpause.
- **Owner CANNOT:** mint LSL, take a user's LSL beyond what the user spends, directly delete a user's
  subscription/credits (only operators consume PerUse credits; nobody can shorten a subscription).
- **Operators CAN:** decrement any user's PerUse credits (`consume`). **CANNOT:** move LSL or touch
  subscriptions.

---

## Proposed hardening — FUTURE VERSION ONLY (do NOT apply to the deployed contract)

> The deployed `LSLAccessGate` (`0x14c129b8D22491a2cCE9Be36137eC8d9B9b31Db5`) is immutable and its source
> is Etherscan-verified against the live bytecode. **Do not edit the deployed source.** Apply the
> following only if you ever redeploy a V2. It closes finding #1 by tracking explicit existence.

```diff
@@ struct Resource @@
     struct Resource {
         uint128 price;
         uint64 duration;
         AccessModel model;
         bool active;
+        bool exists;   // true once configured via setResource; guards setResourceActive
     }

@@ errors @@
     error UnknownOrInactiveResource(bytes32 id);
+    error UnknownResource(bytes32 id);

@@ function setResource @@
     function setResource(bytes32 id, AccessModel model, uint128 price, uint64 duration, bool active)
         external
         onlyOwner
     {
-        resources[id] = Resource({price: price, duration: duration, model: model, active: active});
+        resources[id] = Resource({price: price, duration: duration, model: model, active: active, exists: true});
         emit ResourceSet(id, model, price, duration, active);
     }

@@ function setResourceActive @@
     function setResourceActive(bytes32 id, bool active) external onlyOwner {
-        resources[id].active = active;
         Resource storage r = resources[id];
+        if (!r.exists) revert UnknownResource(id);   // can't activate a never-configured resource
+        r.active = active;
         emit ResourceSet(id, r.model, r.price, r.duration, active);
     }
```

Add a test asserting `setResourceActive(<unconfigured id>, true)` reverts with `UnknownResource`.

(Adding `bool exists` changes the `Resource` storage layout — fine for a fresh deploy, never for an
in-place patch.)

---

## Operational checklist (today, for the live AccessGate)
- [ ] Only `setResourceActive` on resources already created with `setResource` (mitigates #1).
- [ ] Operator key = dedicated, least-privilege backend signer; rotate via `setOperator` if exposed (#2).
- [ ] Consider migrating gate ownership to a multisig if external users rely on stable pricing (#3).
- [ ] Never transfer LSL directly to the gate address — it would be stuck (#4).
