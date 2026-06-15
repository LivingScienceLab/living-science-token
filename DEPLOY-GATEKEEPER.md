# Deploying the LSL AccessGate Gatekeeper

The gatekeeper (`scripts/gatekeeper.mjs`) is the off-chain half of spend-to-access: it authenticates a
caller (SIWE), checks on-chain access against the deployed `LSLAccessGate`
(`0x14c129b8D22491a2cCE9Be36137eC8d9B9b31Db5`), and — for an authorized request — reverse-proxies to your
real service. The contract is the source of truth for payment/entitlement; this process enforces it.

## Prerequisites
- The `LSLAccessGate` is live on mainnet with your resources configured (`scripts/gate.sh resource <id>`).
- An **operator** keystore (for PerUse `consume`) funded with a little ETH — already set up in `.secrets/`.
- `cast` (foundry) available wherever the gatekeeper runs (the Docker image bundles it).

## Required configuration
Set these (via `.env`, `--env-file`, or platform env vars — the gatekeeper merges `.env` with `process.env`,
env vars winning):

| Var | Required | Purpose |
|-----|----------|---------|
| `LSL_ACCESS_GATE_ADDRESS` | yes | the gate to read |
| `GATE_SESSION_SECRET` | **prod** | stable HMAC key for stateless session tokens (survive restarts / scale) |
| `GATE_DOMAIN` | **prod** | your real host; SIWE messages must bind to it (anti-phishing) |
| `OPERATOR_KEYSTORE`, `OPERATOR_KEYSTORE_PW` | for PerUse | signs `consume()` |
| `NETWORK` | no (default `mainnet`) | RPC alias/URL for chain reads |
| `NONCE_RATE_MAX` | no (default 30) | `/nonce` requests per IP/min |
| `PORT` | no (default 8088) | listen port |

Wire your real service per resource in **`gate-upstreams.json`** (gitignored; see
`gate-upstreams.example.json`). Without it, `/serve` returns a placeholder.

## Run it

### Bare (a VM / box with foundry installed)
```
scripts/gatekeeper-run.sh        # validates GATE_SESSION_SECRET + a real GATE_DOMAIN, then runs
# local testing only: ALLOW_INSECURE=1 scripts/gatekeeper-run.sh
```
Use a process manager (systemd / pm2) to keep it up and restart on crash.

### Docker
```
docker build -t lsl-gatekeeper .
docker run -p 8088:8088 --env-file .env \
  -e GATE_DOMAIN=gate.example.org \
  -e OPERATOR_KEYSTORE=/secrets/operator.json \
  -v "$PWD/gate-upstreams.json":/app/gate-upstreams.json:ro \
  -v "$PWD/.secrets/<keystore-file>":/secrets/operator.json:ro \
  lsl-gatekeeper
```
On Cloud Run / similar: push the image, set the env vars, mount the keystore as a secret, and let the
platform terminate TLS and route to `$PORT`.

### Cloud Run (GCP) — one command
`deploy/cloudrun-deploy.sh` does it end to end: builds the image to Artifact Registry (Cloud Build),
pushes your local secrets (`.env` values, operator keystore, `gate-upstreams.json`) to Secret Manager,
creates a least-privilege runtime service account, and deploys the service with env + mounted secrets.
```
gcloud auth login
PROJECT_ID=my-proj GATE_DOMAIN=gate.livingsciencelab.org deploy/cloudrun-deploy.sh
```
Then map your domain so SIWE domain binding matches clients (Cloud Run provides TLS for the mapped domain):
```
gcloud run domain-mappings create --service lsl-gatekeeper --domain gate.livingsciencelab.org --region us-central1
```
Notes:
- **Set `gate-upstreams.json` to your real service first** — it's pushed verbatim into the `gate-upstreams`
  secret (currently the Alchemy demo).
- `NETWORK` is set to the **full RPC URL** (from `MAINNET_RPC_URL`) because the image has no `foundry.toml`
  to resolve the `mainnet` alias.
- **Pinned to one instance** (`--max-instances 1`): single-use nonces are in-memory/per-instance. To scale
  out, move nonces to a shared store (Redis/Memorystore) and raise the cap. Sessions are stateless already.
- Deployed `--allow-unauthenticated` by default (a gatekeeper is public-facing and enforces its **own**
  SIWE auth); set `ALLOW_UNAUTH=0` to require IAM/IAP in front instead.
- Declarative alternative: edit and apply `deploy/cloudrun-gatekeeper.yaml` with
  `gcloud run services replace`.

### Auto-publish the image to Artifact Registry (keyless CI)
So the CI build lands the image in GCP automatically (no Cloud Build step in the deploy), wire up
Workload Identity Federation once — no service-account keys:
```
PROJECT_ID=my-proj GITHUB_REPO=LivingScienceLab/living-science-token deploy/setup-wif.sh
# then set the printed GitHub repo Variables (GCP_WIF_PROVIDER, GCP_DEPLOY_SA, GCP_PROJECT,
# GCP_AR_REGION, GCP_AR_REPO)
```
After that, every gatekeeper/Dockerfile change on `main` (and version tags) pushes the image to both
GHCR **and** `…-docker.pkg.dev/<project>/<repo>/lsl-gatekeeper`. Point the Cloud Run deploy at that
AR image (it's the same tag the deploy script builds).

## TLS
The gatekeeper speaks plain HTTP — **always** put TLS in front. Either a platform LB (Cloud Run, ALB) or a
reverse proxy. Minimal Caddy (automatic HTTPS):
```
gate.example.org {
    reverse_proxy 127.0.0.1:8088
}
```

## Endpoints
- `GET /health` — liveness probe (`{status:"ok",...}`), unauthenticated.
- `GET /nonce` — issue a single-use SIWE nonce (rate-limited).
- `POST /login {message,signature}` — verify SIWE, return a Bearer session token.
- `POST /serve?resource=<id>` — **Bearer required**; checks access, proxies to the upstream (PerUse burns a
  credit only after the upstream succeeds).
- `GET /check?user=0x..&resource=<id>` — public read-only access snapshot.

Reference client: `node scripts/gate-login.mjs --url https://gate.example.org --key 0x.. --serve <id>`
(or `--ledger N`).

## Hardening already in place
Stateless signed sessions, SIWE domain binding + nonce single-use + expiry, `/serve` derives the user from
the session (never a param), `/nonce` rate-limiting, upstream auth never exposed to the client, no SSRF
(upstream URLs are server config). Remaining ops concern: a shared nonce store (e.g. Redis) if you run
multiple instances behind a load balancer.
