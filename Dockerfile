# LSL AccessGate gatekeeper — container image.
# The gatekeeper shells out to `cast` (foundry) for chain reads + operator consume, so we copy the
# cast binary from the official foundry image into a small Node runtime. Secrets are NEVER baked in —
# mount .env / gate-upstreams.json / the operator keystore at runtime.
#
# Build: docker build -t lsl-gatekeeper .
# Run:   docker run -p 8088:8088 \
#          --env-file .env \
#          -e GATE_DOMAIN=gate.livingsciencelab.org \
#          -e OPERATOR_KEYSTORE=/secrets/operator.json \
#          -v "$PWD/gate-upstreams.json":/app/gate-upstreams.json:ro \
#          -v "$PWD/.secrets/<keystore-file>":/secrets/operator.json:ro \
#          lsl-gatekeeper
#   (For Cloud Run: push the image, set env vars + a mounted secret, route TLS via the platform.)
FROM ghcr.io/foundry-rs/foundry:latest AS foundry

FROM node:22-slim
ENV CAST=/usr/local/bin/cast PORT=8088 NODE_ENV=production
# ca-certificates so `cast` can reach HTTPS RPC endpoints; curl is handy for ad-hoc probes.
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*
COPY --from=foundry /usr/local/bin/cast /usr/local/bin/cast
WORKDIR /app
# Only the gatekeeper code is baked in; config + secrets are mounted at runtime.
COPY scripts/gatekeeper.mjs ./scripts/gatekeeper.mjs
EXPOSE 8088
HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:'+(process.env.PORT||8088)+'/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
USER node
CMD ["node", "scripts/gatekeeper.mjs"]
