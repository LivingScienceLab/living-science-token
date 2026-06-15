#!/usr/bin/env bash
# Deploy the LSL AccessGate gatekeeper to Google Cloud Run, end to end:
#   1. build the image -> Artifact Registry (Cloud Build, from the repo Dockerfile)
#   2. push local secrets (.env values, operator keystore, gate-upstreams.json) -> Secret Manager
#   3. deploy the Cloud Run service with env + mounted secrets (single instance; SIWE-enforced)
# Idempotent: safe to re-run (adds new secret versions, updates the service).
#
# Run from the repo root after `gcloud auth login`:
#   PROJECT_ID=my-proj GATE_DOMAIN=gate.livingsciencelab.org deploy/cloudrun-deploy.sh
# Optional: REGION (default us-central1), AR_REPO (lsl), SERVICE (lsl-gatekeeper),
#           ALLOW_UNAUTH (1 = public ingress; default 1 — a gatekeeper is public-facing and does
#           its OWN SIWE auth. Set 0 to require IAM/IAP in front instead.)
set -euo pipefail
cd "$(dirname "$0")/.."

: "${PROJECT_ID:?set PROJECT_ID}"
: "${GATE_DOMAIN:?set GATE_DOMAIN to your real gatekeeper host (SIWE domain binding)}"
REGION="${REGION:-us-central1}"; AR_REPO="${AR_REPO:-lsl}"; SERVICE="${SERVICE:-lsl-gatekeeper}"
RUNTIME_SA="${RUNTIME_SA:-lsl-gatekeeper-run}"; ALLOW_UNAUTH="${ALLOW_UNAUTH:-1}"
IMAGE="${REGION}-docker.pkg.dev/${PROJECT_ID}/${AR_REPO}/lsl-gatekeeper:latest"

command -v gcloud >/dev/null || { echo "FATAL: gcloud not found." >&2; exit 1; }
[ -f .env ] || { echo "FATAL: .env not found (gatekeeper secrets live there)." >&2; exit 1; }
set -a; source .env; set +a
: "${GATE_SESSION_SECRET:?GATE_SESSION_SECRET missing from .env}"
: "${MAINNET_RPC_URL:?MAINNET_RPC_URL missing from .env (used as NETWORK = full RPC URL)}"
: "${OPERATOR_KEYSTORE:?OPERATOR_KEYSTORE missing from .env}"
: "${OPERATOR_KEYSTORE_PW:?OPERATOR_KEYSTORE_PW missing from .env}"
[ -f gate-upstreams.json ] || { echo "FATAL: gate-upstreams.json not found (set your upstream config first)." >&2; exit 1; }
[ -f "$OPERATOR_KEYSTORE" ] || { echo "FATAL: operator keystore file missing: $OPERATOR_KEYSTORE" >&2; exit 1; }

gcloud config set project "$PROJECT_ID" >/dev/null

echo "==> [1/5] enable APIs"
gcloud services enable run.googleapis.com cloudbuild.googleapis.com \
  artifactregistry.googleapis.com secretmanager.googleapis.com

echo "==> [2/5] Artifact Registry repo '$AR_REPO' + build image"
gcloud artifacts repositories describe "$AR_REPO" --location "$REGION" >/dev/null 2>&1 || \
  gcloud artifacts repositories create "$AR_REPO" --repository-format docker --location "$REGION"
gcloud builds submit --tag "$IMAGE" .

echo "==> [3/5] push secrets to Secret Manager"
put_secret() {  # $1 = secret name; data on stdin
  if gcloud secrets describe "$1" >/dev/null 2>&1; then gcloud secrets versions add "$1" --data-file=- >/dev/null
  else gcloud secrets create "$1" --replication-policy=automatic --data-file=- >/dev/null; fi
  echo "    secret: $1"
}
printf %s "$GATE_SESSION_SECRET"  | put_secret gate-session-secret
printf %s "$MAINNET_RPC_URL"      | put_secret gate-rpc-url
printf %s "$OPERATOR_KEYSTORE_PW" | put_secret gate-operator-pw
put_secret gate-operator-keystore < "$OPERATOR_KEYSTORE"
put_secret gate-upstreams         < gate-upstreams.json

echo "==> [4/5] runtime service account + secret access"
SA_EMAIL="${RUNTIME_SA}@${PROJECT_ID}.iam.gserviceaccount.com"
gcloud iam service-accounts describe "$SA_EMAIL" >/dev/null 2>&1 || \
  gcloud iam service-accounts create "$RUNTIME_SA" --display-name "LSL gatekeeper runtime"
for s in gate-session-secret gate-rpc-url gate-operator-pw gate-operator-keystore gate-upstreams; do
  gcloud secrets add-iam-policy-binding "$s" \
    --member "serviceAccount:$SA_EMAIL" --role roles/secretmanager.secretAccessor >/dev/null
done

echo "==> [5/5] deploy Cloud Run service '$SERVICE'"
AUTH_FLAG=$([ "$ALLOW_UNAUTH" = 1 ] && echo --allow-unauthenticated || echo --no-allow-unauthenticated)
gcloud run deploy "$SERVICE" \
  --image "$IMAGE" --region "$REGION" --service-account "$SA_EMAIL" \
  --min-instances 0 --max-instances 1 --concurrency 40 --cpu 1 --memory 512Mi --timeout 300 \
  --session-affinity "$AUTH_FLAG" \
  --set-env-vars "LSL_ACCESS_GATE_ADDRESS=0x14c129b8D22491a2cCE9Be36137eC8d9B9b31Db5,GATE_DOMAIN=${GATE_DOMAIN},NONCE_RATE_MAX=30,OPERATOR_KEYSTORE=/secrets/operator/keystore.json,GATE_UPSTREAMS_FILE=/secrets/upstreams/gate-upstreams.json" \
  --set-secrets "GATE_SESSION_SECRET=gate-session-secret:latest,NETWORK=gate-rpc-url:latest,OPERATOR_KEYSTORE_PW=gate-operator-pw:latest,/secrets/operator/keystore.json=gate-operator-keystore:latest,/secrets/upstreams/gate-upstreams.json=gate-upstreams:latest"

URL=$(gcloud run services describe "$SERVICE" --region "$REGION" --format 'value(status.url)')
echo
echo "Deployed: $URL"
echo "Health  : curl $URL/health"
echo "NEXT: map $GATE_DOMAIN to the service (gcloud run domain-mappings create) so SIWE domain binding"
echo "      matches clients; Cloud Run provides TLS for the mapped domain. max-instances=1 (in-memory"
echo "      nonces) — raise only with a shared nonce store (Redis/Memorystore)."
