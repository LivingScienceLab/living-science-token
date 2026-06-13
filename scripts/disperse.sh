#!/usr/bin/env bash
# Safe LSL batch distribution via LSLDisperse: dry-run (simulate approve+disperse) first,
# then ask before a Ledger-signed broadcast. Two transactions total, regardless of recipient count.
# Usage: scripts/disperse.sh [network]   (network defaults to "mainnet"; use "sepolia" to rehearse)
#
# Requires LSL_DISPERSE (the deployed LSLDisperse address) in .env or the environment.
# Deploy the helper once with: forge script script/DeployDisperse.s.sol:DeployDisperse ...
set -euo pipefail

cd "$(dirname "$0")/.."
export PATH="$HOME/.config/.foundry/bin:$PATH"

if [ ! -f .env ]; then echo "ERROR: .env not found (copy .env.example and fill it in)." >&2; exit 1; fi
set -a; source .env; set +a
: "${LEDGER_SENDER:?LEDGER_SENDER must be set in .env}"
: "${LSL_DISPERSE:?LSL_DISPERSE (deployed LSLDisperse address) must be set in .env or the environment}"

NET="${1:-mainnet}"
CFG="${DISTRIBUTION_FILE:-distribution.json}"
if [ ! -f "$CFG" ]; then
  echo "ERROR: $CFG not found. Copy distribution.example.json to distribution.json and edit it." >&2
  exit 1
fi

echo "=============================================="
echo " DRY RUN (simulation only — NO signature sent)"
echo " network: $NET   config: $CFG"
echo " signer:  $LEDGER_SENDER"
echo " disperser: $LSL_DISPERSE"
echo "=============================================="
forge script script/DisperseBatch.s.sol:DisperseBatch --rpc-url "$NET" --sender "$LEDGER_SENDER" -vvvv

echo
echo "Review the preview above carefully (recipients, amounts, total, remaining)."
echo "Broadcast sends TWO Ledger-signed transactions: (1) approve, then (2) disperse."
read -r -p "Broadcast for REAL on $NET, signed by your Ledger? Type 'yes' to proceed: " CONFIRM
if [ "$CONFIRM" != "yes" ]; then echo "Aborted — nothing was sent."; exit 0; fi

echo ">>> Confirm BOTH transactions on your Ledger (Ethereum app, blind signing on) <<<"
# --slow waits for the approve to confirm before sending the disperse (which depends on it).
forge script script/DisperseBatch.s.sol:DisperseBatch --rpc-url "$NET" \
  --ledger --sender "$LEDGER_SENDER" --broadcast --slow -vvvv
