#!/bin/sh
# Combined-image entrypoint: run BOTH halves of spend-to-access in one container —
#   - the Python IP-asset service  (loopback 127.0.0.1:$ASSET_PORT — gatekeeper-only)
#   - the Node gatekeeper          (public :$PORT — SIWE + on-chain payment)
# The gatekeeper proxies to the asset service over loopback (gate-upstreams.json ->
# http://127.0.0.1:8090/asset). If EITHER process exits, the whole container exits
# non-zero so the platform (Cloud Run / Docker restart policy) restarts it — never a
# silent half-up state where the gatekeeper 502s because the asset service is gone.
set -eu

APP_DIR="${APP_DIR:-/app}"        # overridable for local testing outside the image

echo "[entrypoint] asset service -> 127.0.0.1:${ASSET_PORT:-8090} (loopback, gatekeeper-only)"
python3 "$APP_DIR/asset-service/serve.py" &
ASSET_PID=$!

echo "[entrypoint] gatekeeper   -> :${PORT:-8088} (public, SIWE + on-chain)"
node "$APP_DIR/scripts/gatekeeper.mjs" &
GK_PID=$!

cleanup() { kill -TERM "$ASSET_PID" "$GK_PID" 2>/dev/null || true; }

# Deliberate stop (Cloud Run / `docker stop` send SIGTERM): tear down both, exit 0 so
# `--restart on-failure` does NOT treat a clean shutdown as a crash.
on_signal() {
  echo "[entrypoint] signal received — stopping children"
  cleanup; wait 2>/dev/null || true
  exit 0
}
trap on_signal TERM INT

# Exit as soon as EITHER child dies unexpectedly (portable: dash has no `wait -n`).
while kill -0 "$ASSET_PID" 2>/dev/null && kill -0 "$GK_PID" 2>/dev/null; do
  sleep 1
done

kill -0 "$ASSET_PID" 2>/dev/null || echo "[entrypoint] asset service exited — bringing container down"
kill -0 "$GK_PID"    2>/dev/null || echo "[entrypoint] gatekeeper exited — bringing container down"
cleanup
wait 2>/dev/null || true
exit 1   # a child crashed → non-zero so the platform restarts the container
