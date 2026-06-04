#!/usr/bin/env bash
#
# One-shot: create the private GitHub repo, push, and configure the CSR mirror.
# Run this ONLY after you have authenticated:
#     gh auth login          # (writes ~/.config/gh)
#     gcloud auth login      # (writes ~/.config/gcloud)  -- needed for the CSR push
#
# Usage:
#     CSR_URL="https://source.developers.google.com/p/PROJECT/r/REPO" \
#       bash scripts/push-and-mirror.sh
#
set -euo pipefail

REPO_NAME="living-science-token"
VISIBILITY="--private"
CSR_URL="${CSR_URL:-}"

cd "$(dirname "$0")/.."

echo "==> Checking GitHub auth..."
gh auth status >/dev/null 2>&1 || { echo "ERROR: run 'gh auth login' first."; exit 1; }

echo "==> Creating GitHub repo and pushing 'main'..."
# Creates the repo under your account, sets 'origin', and pushes.
gh repo create "$REPO_NAME" $VISIBILITY --source=. --remote=origin --push

if [[ -n "$CSR_URL" ]]; then
  echo "==> Configuring Google Cloud as git credential helper..."
  git config --global credential."https://source.developers.google.com".helper \
    '!gcloud auth git-helper --account="$(gcloud config get-value account)" --ignore-unknown $@' || true

  echo "==> Adding CSR as a second push URL on 'origin' (single push -> both remotes)..."
  git remote set-url --add --push origin "$(git remote get-url origin)"  # keep GitHub push
  git remote set-url --add --push origin "$CSR_URL"                       # add CSR push

  echo "==> Pushing to the mirror..."
  git push origin main

  echo "==> Done. 'git push' now updates BOTH GitHub and CSR."
else
  echo "NOTE: CSR_URL not set -> GitHub only. Re-run with CSR_URL=... to add the mirror."
fi

echo ""
echo "Remotes:"
git remote -v
