#!/usr/bin/env bash
# Production launcher for the LSL AccessGate gatekeeper. Validates required config, then runs the
# Node server (which shells out to `cast`, so foundry must be on PATH). Put TLS in front of this
# (reverse proxy / load balancer) — see DEPLOY-GATEKEEPER.md.
#
# Usage: scripts/gatekeeper-run.sh
# Env (from .env or the environment):
#   GATE_DOMAIN          REQUIRED in prod — your real host (SIWE domain binding). Refuses localhost.
#   GATE_SESSION_SECRET  REQUIRED in prod — stable HMAC key (sessions drop/forge across restarts if unset).
#   PORT                 listen port (default 8088).
#   NETWORK              RPC alias/URL for chain reads (default mainnet).
#   LSL_ACCESS_GATE_ADDRESS, OPERATOR_KEYSTORE/_PW (for PerUse consume) — from .env.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.config/.foundry/bin:$PATH"
[ -f .env ] && { set -a; source .env; set +a; }

command -v cast >/dev/null || { echo "FATAL: 'cast' (foundry) not on PATH." >&2; exit 1; }
command -v node >/dev/null || { echo "FATAL: 'node' not on PATH." >&2; exit 1; }
: "${LSL_ACCESS_GATE_ADDRESS:?set LSL_ACCESS_GATE_ADDRESS in .env}"

ALLOW_INSECURE="${ALLOW_INSECURE:-0}"
fail=0
if [ -z "${GATE_SESSION_SECRET:-}" ]; then
  echo "WARN: GATE_SESSION_SECRET unset — sessions will not survive a restart and won't validate across instances." >&2
  [ "$ALLOW_INSECURE" = 1 ] || fail=1
fi
case "${GATE_DOMAIN:-}" in
  ""|localhost*|127.0.0.1*)
    echo "WARN: GATE_DOMAIN is unset/localhost — SIWE domain binding won't match a real client origin." >&2
    [ "$ALLOW_INSECURE" = 1 ] || fail=1 ;;
esac
if [ -f gate-upstreams.json ]; then
  echo "upstreams: $(node -e 'const u=require("./gate-upstreams.json");console.log(Object.keys(u).filter(k=>!k.startsWith("_")).join(", ")||"(none)")')"
else
  echo "NOTE: gate-upstreams.json not found — /serve will return the placeholder payload (no real proxy)." >&2
fi
if [ "$fail" = 1 ]; then
  echo "Refusing to start without GATE_SESSION_SECRET + a real GATE_DOMAIN. Set them, or re-run with ALLOW_INSECURE=1 for local testing." >&2
  exit 1
fi

echo "Starting gatekeeper on :${PORT:-8088}  (gate $LSL_ACCESS_GATE_ADDRESS, net ${NETWORK:-mainnet}, domain ${GATE_DOMAIN:-localhost})"
exec node scripts/gatekeeper.mjs
