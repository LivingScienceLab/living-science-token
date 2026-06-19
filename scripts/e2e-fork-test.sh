#!/usr/bin/env bash
# End-to-end test of spend-to-access on a MAINNET FORK (anvil) — exercises the real, deployed
# LSL token + LSLAccessGate plus the off-chain gatekeeper and the IP-asset service together.
#
# What it proves (nothing is mocked except the chain is a local fork of mainnet state):
#   PHASE 1 — Subscription (the live `research-access` resource):
#     buyer funds LSL -> approve -> purchase(1 period) -> hasAccess==true
#     -> SIWE login -> POST /serve?resource=research-access -> 200 + the actual dataset+manifest
#     -> a NON-buyer's /serve is denied 402.
#   PHASE 2 — PerUse burn mandate (a throwaway resource provisioned on the fork):
#     owner setResource(PerUse) + setOperator -> buyer purchases 3 credits
#     -> /serve consumes exactly ONE credit on-chain via the operator key (3 -> 2).
#
# Requires foundry (anvil/cast) + node + python3, and MAINNET_RPC_URL in .env. Touches NO mainnet
# state and signs nothing real — anvil's default dev keys are used as buyers; all txs hit the fork.
set -euo pipefail
cd "$(dirname "$0")/.."

CAST="${CAST:-$HOME/.config/.foundry/bin/cast}"
ANVIL="${ANVIL:-$HOME/.config/.foundry/bin/anvil}"
[ -x "$CAST" ] || CAST="$HOME/.foundry/bin/cast"
[ -x "$ANVIL" ] || ANVIL="$HOME/.foundry/bin/anvil"

# --- config (read deployed addresses from .env; fixed test identities) ---
set -a; . ./.env; set +a
GATE="${LSL_ACCESS_GATE_ADDRESS:?}"; LSL="${LSL_TOKEN_ADDRESS:?}"
OWNER=0x7C9eF832417e63F805ccaAbD131741aceEB5Bc1a            # gate owner + LSL holder (the deployer)
OPERATOR="${OPERATOR_ADDRESS:?}"
FORK_PORT=8545; GK_PORT=8088; ASSET_PORT=8090
RPC="http://127.0.0.1:$FORK_PORT"; GK="http://localhost:$GK_PORT"   # host must match GATE_DOMAIN for SIWE
# anvil deterministic dev accounts 0 (buyer) and 1 (non-buyer) — funded with ETH by anvil even on a fork.
BUYER_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
BUYER=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
OUTSIDER_KEY=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
RESEARCH_ID=$("$CAST" format-bytes32-string research-access)
PERUSE_ID=$("$CAST" format-bytes32-string e2e-ai-call)
e18() { echo "${1}000000000000000000"; }                    # whole LSL -> wei (integers only)

PIDS=()
cleanup() {
  echo "--- cleanup ---"
  for p in "${PIDS[@]:-}"; do kill "$p" 2>/dev/null || true; done
  wait 2>/dev/null || true
}
trap cleanup EXIT
fail() { echo "❌ FAIL: $*" >&2; exit 1; }
ok()   { echo "✅ $*"; }

# wait until a command succeeds (readiness probe)
wait_for() { local n=0; until eval "$1" >/dev/null 2>&1; do n=$((n+1)); [ "$n" -gt 60 ] && fail "timeout: $2"; sleep 0.5; done; }

# free the ports we need
for port in $FORK_PORT $GK_PORT $ASSET_PORT; do
  pid=$(ss -ltnp 2>/dev/null | grep ":$port " | grep -oE 'pid=[0-9]+' | head -1 | cut -d= -f2 || true)
  [ -n "${pid:-}" ] && { echo "freeing port $port (pid $pid)"; kill -9 "$pid" 2>/dev/null || true; }
done

echo "==================== START FORK ===================="
"$ANVIL" --fork-url "${MAINNET_RPC_URL:?}" --port "$FORK_PORT" --silent >/tmp/e2e-anvil.log 2>&1 &
PIDS+=($!)
wait_for "\"$CAST\" block-number --rpc-url $RPC" "anvil fork to come up"
ok "anvil forked mainnet (block $("$CAST" block-number --rpc-url "$RPC"))"

echo "==================== FUND BUYER (LSL) ===================="
"$CAST" rpc anvil_setBalance "$OWNER" 0x21e19e0c9bab2400000 --rpc-url "$RPC" >/dev/null   # 10000 ETH for gas
"$CAST" rpc anvil_impersonateAccount "$OWNER" --rpc-url "$RPC" >/dev/null
"$CAST" send "$LSL" "transfer(address,uint256)" "$BUYER" "$(e18 200)" --from "$OWNER" --unlocked --rpc-url "$RPC" >/dev/null
BAL=$("$CAST" call "$LSL" "balanceOf(address)(uint256)" "$BUYER" --rpc-url "$RPC" | awk '{print $1}')
[ "$BAL" = "$(e18 200)" ] || fail "buyer LSL funding (got $BAL)"
ok "buyer funded: 200 LSL"

echo "==================== PHASE 1: SUBSCRIPTION (research-access) ===================="
"$CAST" send "$LSL" "approve(address,uint256)" "$GATE" "$(e18 50)" --private-key "$BUYER_KEY" --rpc-url "$RPC" >/dev/null
"$CAST" send "$GATE" "purchase(bytes32,uint256)" "$RESEARCH_ID" 1 --private-key "$BUYER_KEY" --rpc-url "$RPC" >/dev/null
ACC=$("$CAST" call "$GATE" "hasAccess(address,bytes32)(bool)" "$BUYER" "$RESEARCH_ID" --rpc-url "$RPC")
[ "$ACC" = "true" ] || fail "hasAccess after purchase (got $ACC)"
ok "purchased 1 subscription period; hasAccess=true"

echo "==================== START ASSET SERVICE + GATEKEEPER (-> fork) ===================="
# launch python3 directly (no subshell) so the trapped PID is the server itself, not a wrapper
ASSET_OUT_DIR=/tmp/lsl-e2e-out ASSET_PORT=$ASSET_PORT python3 asset-service/serve.py >/tmp/e2e-asset.log 2>&1 &
PIDS+=($!)
wait_for "curl -sf http://127.0.0.1:$ASSET_PORT/health" "asset service"
NETWORK="$RPC" LSL_ACCESS_GATE_ADDRESS="$GATE" GATE_SESSION_SECRET=e2e-secret GATE_DOMAIN="localhost:$GK_PORT" \
  PORT=$GK_PORT node scripts/gatekeeper.mjs >/tmp/e2e-gk.log 2>&1 &
PIDS+=($!)
wait_for "curl -sf $GK/health" "gatekeeper /health"
ok "asset service (:$ASSET_PORT) + gatekeeper (:$GK_PORT) up, pointed at the fork"

echo "==================== PHASE 1 CLIENT: SIWE -> /serve (buyer, expect 200 + asset) ===================="
node scripts/gate-login.mjs --url "$GK" --key "$BUYER_KEY" --serve research-access >/tmp/e2e-buyer.out 2>&1 || true
cat /tmp/e2e-buyer.out
grep -q "/serve research-access -> 200" /tmp/e2e-buyer.out || fail "buyer /serve not 200"
grep -q '"content_sha256"' /tmp/e2e-buyer.out || fail "asset manifest not returned"
grep -q '"dataset"' /tmp/e2e-buyer.out || fail "asset dataset not returned"
ok "buyer got the IP asset over the full SIWE+on-chain path"

echo "==================== PHASE 1 NEGATIVE: non-buyer -> /serve (expect 402) ===================="
node scripts/gate-login.mjs --url "$GK" --key "$OUTSIDER_KEY" --serve research-access >/tmp/e2e-out.out 2>&1 || true
grep -q "/serve research-access -> 402" /tmp/e2e-out.out || { cat /tmp/e2e-out.out; fail "non-buyer was NOT denied"; }
ok "non-buyer correctly denied (402)"

echo "==================== PHASE 2: PERUSE BURN/CONSUME (e2e-ai-call) ===================="
# owner provisions a PerUse resource (price 10 LSL/use) and authorizes the operator backend.
"$CAST" send "$GATE" "setResource(bytes32,uint8,uint128,uint64,bool)" "$PERUSE_ID" 0 "$(e18 10)" 0 true --from "$OWNER" --unlocked --rpc-url "$RPC" >/dev/null
"$CAST" send "$GATE" "setOperator(address,bool)" "$OPERATOR" true --from "$OWNER" --unlocked --rpc-url "$RPC" >/dev/null
"$CAST" rpc anvil_setBalance "$OPERATOR" 0xde0b6b3a7640000 --rpc-url "$RPC" >/dev/null   # 1 ETH gas for consume()
"$CAST" rpc anvil_stopImpersonatingAccount "$OWNER" --rpc-url "$RPC" >/dev/null
# buyer buys 3 credits
"$CAST" send "$LSL" "approve(address,uint256)" "$GATE" "$(e18 30)" --private-key "$BUYER_KEY" --rpc-url "$RPC" >/dev/null
"$CAST" send "$GATE" "purchase(bytes32,uint256)" "$PERUSE_ID" 3 --private-key "$BUYER_KEY" --rpc-url "$RPC" >/dev/null
C0=$("$CAST" call "$GATE" "credits(address,bytes32)(uint256)" "$BUYER" "$PERUSE_ID" --rpc-url "$RPC" | awk '{print $1}')
[ "$C0" = "3" ] || fail "expected 3 credits after purchase (got $C0)"
ok "purchased 3 PerUse credits"
# /serve must consume exactly one (the gatekeeper uses the operator keystore from .env)
node scripts/gate-login.mjs --url "$GK" --key "$BUYER_KEY" --serve e2e-ai-call >/tmp/e2e-peruse.out 2>&1 || true
cat /tmp/e2e-peruse.out
grep -q "/serve e2e-ai-call -> 200" /tmp/e2e-peruse.out || fail "PerUse /serve not 200 (operator keystore configured?)"
C1=$("$CAST" call "$GATE" "credits(address,bytes32)(uint256)" "$BUYER" "$PERUSE_ID" --rpc-url "$RPC" | awk '{print $1}')
[ "$C1" = "2" ] || fail "expected 2 credits after one /serve (got $C1)"
ok "exactly ONE credit consumed on-chain (3 -> 2) — burn mandate works"

echo; echo "🎉 ALL E2E CHECKS PASSED (mainnet fork)"
