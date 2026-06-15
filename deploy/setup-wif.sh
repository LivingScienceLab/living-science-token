#!/usr/bin/env bash
# One-time: configure GCP Workload Identity Federation so the GitHub Actions image workflow can push
# to Artifact Registry WITHOUT any long-lived service-account key (keyless, via GitHub's OIDC token).
# Run once as a project admin after `gcloud auth login`. Prints the repo Variables to set afterward.
#
#   PROJECT_ID=my-proj GITHUB_REPO=LivingScienceLab/living-science-token deploy/setup-wif.sh
# Optional: REGION (us-central1), AR_REPO (lsl), POOL (github), PROVIDER (github-provider),
#           SA (gha-image-pusher).
set -euo pipefail
: "${PROJECT_ID:?set PROJECT_ID}"
: "${GITHUB_REPO:?set GITHUB_REPO as owner/name (e.g. LivingScienceLab/living-science-token)}"
REGION="${REGION:-us-central1}"; AR_REPO="${AR_REPO:-lsl}"
POOL="${POOL:-github}"; PROVIDER="${PROVIDER:-github-provider}"; SA="${SA:-gha-image-pusher}"
OWNER="${GITHUB_REPO%%/*}"
SA_EMAIL="${SA}@${PROJECT_ID}.iam.gserviceaccount.com"

command -v gcloud >/dev/null || { echo "FATAL: gcloud not found." >&2; exit 1; }
gcloud config set project "$PROJECT_ID" >/dev/null
gcloud services enable iamcredentials.googleapis.com sts.googleapis.com artifactregistry.googleapis.com

echo "==> Artifact Registry repo '$AR_REPO'"
gcloud artifacts repositories describe "$AR_REPO" --location "$REGION" >/dev/null 2>&1 || \
  gcloud artifacts repositories create "$AR_REPO" --repository-format docker --location "$REGION"

echo "==> image-pusher service account + Artifact Registry writer"
gcloud iam service-accounts describe "$SA_EMAIL" >/dev/null 2>&1 || \
  gcloud iam service-accounts create "$SA" --display-name "GitHub Actions image pusher"
gcloud artifacts repositories add-iam-policy-binding "$AR_REPO" --location "$REGION" \
  --member "serviceAccount:$SA_EMAIL" --role roles/artifactregistry.writer >/dev/null

echo "==> Workload Identity Pool + GitHub OIDC provider (restricted to owner '$OWNER')"
gcloud iam workload-identity-pools describe "$POOL" --location global >/dev/null 2>&1 || \
  gcloud iam workload-identity-pools create "$POOL" --location global --display-name "GitHub Actions"
gcloud iam workload-identity-pools providers describe "$PROVIDER" --location global \
  --workload-identity-pool "$POOL" >/dev/null 2>&1 || \
  gcloud iam workload-identity-pools providers create-oidc "$PROVIDER" --location global \
    --workload-identity-pool "$POOL" --issuer-uri "https://token.actions.githubusercontent.com" \
    --attribute-mapping "google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner" \
    --attribute-condition "assertion.repository_owner=='${OWNER}'"

echo "==> allow ONLY repo '$GITHUB_REPO' to impersonate the pusher SA"
POOL_NAME=$(gcloud iam workload-identity-pools describe "$POOL" --location global --format 'value(name)')
gcloud iam service-accounts add-iam-policy-binding "$SA_EMAIL" \
  --role roles/iam.workloadIdentityUser \
  --member "principalSet://iam.googleapis.com/${POOL_NAME}/attribute.repository/${GITHUB_REPO}" >/dev/null

PROVIDER_NAME=$(gcloud iam workload-identity-pools providers describe "$PROVIDER" --location global \
  --workload-identity-pool "$POOL" --format 'value(name)')

cat <<EOF

✅ WIF ready. Set these GitHub repo Variables (non-secret identifiers):

  gh variable set GCP_WIF_PROVIDER -R $GITHUB_REPO -b '$PROVIDER_NAME'
  gh variable set GCP_DEPLOY_SA    -R $GITHUB_REPO -b '$SA_EMAIL'
  gh variable set GCP_PROJECT      -R $GITHUB_REPO -b '$PROJECT_ID'
  gh variable set GCP_AR_REGION    -R $GITHUB_REPO -b '$REGION'
  gh variable set GCP_AR_REPO      -R $GITHUB_REPO -b '$AR_REPO'

After that, the next build also pushes to:
  $REGION-docker.pkg.dev/$PROJECT_ID/$AR_REPO/lsl-gatekeeper
Point cloudrun-deploy.sh / cloudrun-gatekeeper.yaml at that same image.
EOF
