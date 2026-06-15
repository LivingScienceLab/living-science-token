#!/usr/bin/env bash
# LSL Access Gate operations CLI — read-only views, buyer purchases, and operator redemptions.
#
# Resource IDs are the SAME encoding used by the live `research-access` resource: a short
# (<=31 char) string RIGHT-PADDED to bytes32 via `cast format-bytes32-string`, NOT keccak256.
# Always pass the human string (e.g. "research-access") and this script encodes it for you.
#
# Usage:
#   scripts/gate.sh id <string>                     # show the bytes32 id for a string
#   scripts/gate.sh status                          # gate-wide config (sink/treasury/paused/owner)
#   scripts/gate.sh resource <id>                   # one resource's price/duration/model/active
#   scripts/gate.sh quote <id> <qty>                # total LSL (wei + whole) for qty units
#   scripts/gate.sh access <user> <id>              # hasAccess + credits/expiry for a user
#   scripts/gate.sh buy <id> <qty> [hdIndex]        # approve + purchase, signed by a Ledger path
#                                                   #   (hdIndex default 1 = m/44'/60'/0'/0/1)
#   scripts/gate.sh consume <user> <id> <amount>    # operator redeems PerUse credits (hot key)
#
# Reads LSL_ACCESS_GATE_ADDRESS, LSL_TOKEN_ADDRESS, OPERATOR_* and an RPC alias from .env.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.config/.foundry/bin:$PATH"
[ -f .env ] || { echo "ERROR: .env not found." >&2; exit 1; }
set -a; source .env; set +a

NET="${NETWORK:-mainnet}"
GATE="${LSL_ACCESS_GATE_ADDRESS:?set LSL_ACCESS_GATE_ADDRESS in .env}"
TOKEN="${LSL_TOKEN_ADDRESS:?set LSL_TOKEN_ADDRESS in .env}"

# Encode a human resource string to the right-padded bytes32 the gate stores.
rid() { cast format-bytes32-string "$1"; }
# Strip cast's "[5e19]"-style annotation, keeping just the integer.
n() { echo "${1%% *}"; }
# Pretty-print a wei amount as whole LSL (tolerates the annotation).
lsl() { cast to-unit "$(n "$1")" ether; }

cmd="${1:-}"; shift || true
case "$cmd" in
  id)
    [ $# -eq 1 ] || { echo "usage: gate.sh id <string>" >&2; exit 1; }
    rid "$1"
    ;;

  status)
    echo "gate     : $GATE"
    echo "token    : $(cast call "$GATE" 'token()(address)' --rpc-url "$NET")"
    s=$(cast call "$GATE" 'sink()(uint8)' --rpc-url "$NET")
    echo "sink     : $s ($([ "$s" = 0 ] && echo Treasury || echo Burn))"
    echo "treasury : $(cast call "$GATE" 'treasury()(address)' --rpc-url "$NET")"
    echo "paused   : $(cast call "$GATE" 'paused()(bool)' --rpc-url "$NET")"
    echo "owner    : $(cast call "$GATE" 'owner()(address)' --rpc-url "$NET")"
    ;;

  resource)
    [ $# -eq 1 ] || { echo "usage: gate.sh resource <id>" >&2; exit 1; }
    ID=$(rid "$1")
    mapfile -t R < <(cast call "$GATE" \
      'resources(bytes32)(uint128,uint64,uint8,bool)' "$ID" --rpc-url "$NET")
    price=$(n "${R[0]}"); duration=$(n "${R[1]}"); model=$(n "${R[2]}"); active="${R[3]}"
    echo "resource : $1"
    echo "id       : $ID"
    echo "model    : $model ($([ "$model" = 0 ] && echo PerUse || echo Subscription))"
    echo "price    : $price wei ($(lsl "$price") LSL per unit)"
    echo "duration : $duration s ($([ "$duration" -gt 0 ] && echo "$((duration/86400)) days" || echo n/a))"
    echo "active   : $active"
    ;;

  quote)
    [ $# -eq 2 ] || { echo "usage: gate.sh quote <id> <qty>" >&2; exit 1; }
    ID=$(rid "$1")
    q=$(n "$(cast call "$GATE" 'quote(bytes32,uint256)(uint256)' "$ID" "$2" --rpc-url "$NET")")
    echo "$q wei ($(lsl "$q") LSL) for $2 unit(s) of '$1'"
    ;;

  access)
    [ $# -eq 2 ] || { echo "usage: gate.sh access <user> <id>" >&2; exit 1; }
    ID=$(rid "$2")
    echo "user     : $1"
    echo "resource : $2"
    echo "hasAccess: $(cast call "$GATE" 'hasAccess(address,bytes32)(bool)' "$1" "$ID" --rpc-url "$NET")"
    echo "credits  : $(cast call "$GATE" 'credits(address,bytes32)(uint256)' "$1" "$ID" --rpc-url "$NET")"
    echo "expiry   : $(cast call "$GATE" 'accessExpiry(address,bytes32)(uint64)' "$1" "$ID" --rpc-url "$NET") (unix)"
    ;;

  buy)
    [ $# -ge 2 ] || { echo "usage: gate.sh buy <id> <qty> [hdIndex]" >&2; exit 1; }
    ID=$(rid "$1"); QTY="$2"; IDX="${3:-1}"
    HDP="m/44'/60'/0'/0/$IDX"
    BUYER=$(cast wallet address --ledger --mnemonic-derivation-path "$HDP")
    COST=$(cast call "$GATE" 'quote(bytes32,uint256)(uint256)' "$ID" "$QTY" --rpc-url "$NET")
    echo "buyer    : $BUYER (Ledger $HDP)"
    echo "resource : $1  qty $QTY"
    echo "cost     : $(lsl "$COST") LSL"
    echo "balance  : $(lsl "$(cast call "$TOKEN" 'balanceOf(address)(uint256)' "$BUYER" --rpc-url "$NET")") LSL"
    read -r -p "Approve $((COST)) wei then purchase, signed by your Ledger? Type 'yes': " C
    [ "$C" = yes ] || { echo "Aborted."; exit 0; }
    echo ">>> Confirm APPROVE on the Ledger <<<"
    cast send "$TOKEN" 'approve(address,uint256)' "$GATE" "$COST" \
      --rpc-url "$NET" --ledger --mnemonic-derivation-path "$HDP"
    echo ">>> Confirm PURCHASE on the Ledger <<<"
    cast send "$GATE" 'purchase(bytes32,uint256)' "$ID" "$QTY" \
      --rpc-url "$NET" --ledger --mnemonic-derivation-path "$HDP"
    echo "Done. New access:"
    "$0" access "$BUYER" "$1"
    ;;

  consume)
    [ $# -eq 3 ] || { echo "usage: gate.sh consume <user> <id> <amount>" >&2; exit 1; }
    : "${OPERATOR_KEYSTORE:?OPERATOR_KEYSTORE not set}"; : "${OPERATOR_KEYSTORE_PW:?OPERATOR_KEYSTORE_PW not set}"
    ID=$(rid "$2")
    echo "operator redeeming $3 credit(s) of '$2' for $1 ..."
    cast send "$GATE" 'consume(address,bytes32,uint256)' "$1" "$ID" "$3" \
      --rpc-url "$NET" --keystore "$OPERATOR_KEYSTORE" --password "$OPERATOR_KEYSTORE_PW"
    "$0" access "$1" "$2"
    ;;

  *)
    grep -E '^#( |$)' "$0" | sed -E 's/^# ?//'
    exit 1
    ;;
esac
