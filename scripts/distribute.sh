#!/usr/bin/env bash
# Safe LSL distribution: dry-run (simulate) first, then ask before a Ledger-signed broadcast.
# Usage: scripts/distribute.sh [network]   (network defaults to "mainnet"; use "sepolia" to rehearse)
set -euo pipefail

cd "$(dirname "$0")/.."
export PATH="$HOME/.config/.foundry/bin:$PATH"

if [ ! -f .env ]; then echo "ERROR: .env not found (copy .env.example and fill it in)." >&2; exit 1; fi
set -a; source .env; set +a
: "${LEDGER_SENDER:?LEDGER_SENDER must be set in .env}"

NET="${1:-mainnet}"
CFG="${DISTRIBUTION_FILE:-distribution.json}"
if [ ! -f "$CFG" ]; then
  echo "ERROR: $CFG not found. Copy distribution.example.json to distribution.json and edit it." >&2
  exit 1
fi

echo "=============================================="
echo " DRY RUN (simulation only — NO signature sent)"
echo " network: $NET   config: $CFG   signer: $LEDGER_SENDER"
echo "=============================================="
forge script script/Distribute.s.sol:Distribute --rpc-url "$NET" --sender "$LEDGER_SENDER" -vvvv

echo
echo "Review the preview above carefully (recipients, amounts, total, remaining)."
read -r -p "Broadcast for REAL on $NET, signed by your Ledger? Type 'yes' to proceed: " CONFIRM
if [ "$CONFIRM" != "yes" ]; then echo "Aborted — nothing was sent."; exit 0; fi

echo ">>> Confirm each transaction on your Ledger (Ethereum app, blind signing on) <<<"
forge script script/Distribute.s.sol:Distribute --rpc-url "$NET" \
  --ledger --sender "$LEDGER_SENDER" --broadcast -vvvv
