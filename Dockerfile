# LSL spend-to-access — COMBINED container image (gatekeeper + IP-asset service).
#
# Runs both halves of spend-to-access in one container:
#   - Node gatekeeper (public :$PORT)  — SIWE auth + on-chain payment; shells out to `cast`.
#   - Python IP-asset service (loopback 127.0.0.1:$ASSET_PORT) — serves the dataset + manifest.
# The gatekeeper proxies to the asset service over loopback (gate-upstreams.json points
# research-access -> http://127.0.0.1:8090/asset). Only the gatekeeper port is exposed.
#
# Secrets are NEVER baked in — mount .env / gate-upstreams.json / the operator keystore at runtime.
# The asset service is vendored under asset-service/ from the living-science-lab repo via
# scripts/sync-asset-service.sh (that repo is the source of truth; re-sync + rebuild after changes).
#
# Build: scripts/sync-asset-service.sh && docker build -t lsl-gatekeeper .
# Run:   docker run -p 8088:8088 \
#          --env-file .env \
#          -e GATE_DOMAIN=gate.livingsciencelab.org \
#          -e OPERATOR_KEYSTORE=/secrets/operator.json \
#          -v "$PWD/gate-upstreams.json":/app/gate-upstreams.json:ro \
#          -v "$PWD/.secrets/<keystore-file>":/secrets/operator.json:ro \
#          lsl-gatekeeper
#   (For Cloud Run: deploy/cloudrun-deploy.sh; the platform terminates TLS and routes to $PORT.)
FROM ghcr.io/foundry-rs/foundry:latest AS foundry

FROM node:22-slim
# PORT     — gatekeeper listen port (Cloud Run overrides this; only this port is public).
# ASSET_*  — the loopback IP-asset service. ASSET_OUT_DIR is /tmp so first-request writes
#            succeed even on a read-only/ephemeral container FS.
ENV CAST=/usr/local/bin/cast PORT=8088 NODE_ENV=production \
    ASSET_HOST=127.0.0.1 ASSET_PORT=8090 ASSET_OUT_DIR=/tmp/lsl-asset-out
# ca-certificates so `cast` can reach HTTPS RPC endpoints; python3 to run the asset service
# (stdlib only — no pip).
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates python3 \
    && rm -rf /var/lib/apt/lists/*
COPY --from=foundry /usr/local/bin/cast /usr/local/bin/cast
WORKDIR /app
# Code is baked in; config + secrets are mounted at runtime.
COPY scripts/gatekeeper.mjs ./scripts/gatekeeper.mjs
COPY asset-service ./asset-service
COPY deploy/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh
EXPOSE 8088
# Container health = the public gatekeeper. (If the asset service dies, the entrypoint exits the
# whole container, so a healthy gatekeeper implies both are up.)
HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:'+(process.env.PORT||8088)+'/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
USER node
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
