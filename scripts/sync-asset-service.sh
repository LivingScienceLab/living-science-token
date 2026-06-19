#!/usr/bin/env bash
# Refresh the vendored asset-service snapshot from the source-of-truth Living Science Lab repo.
#
# The combined Docker image builds from THIS repo's context (`gcloud builds submit .`), so the
# Python IP-asset service must be vendored here under asset-service/. living-science-lab is the
# source of truth — re-run this after changing the pipeline or serve.py there, then rebuild the image.
#
# Usage: scripts/sync-asset-service.sh            # reads from ~/living-science-lab
#        LAB_DIR=/path/to/living-science-lab scripts/sync-asset-service.sh
set -euo pipefail

SRC="${LAB_DIR:-$HOME/living-science-lab}"
DST="$(cd "$(dirname "$0")/.." && pwd)/asset-service"

[ -f "$SRC/serve.py" ] || { echo "ERROR: source not found at $SRC/serve.py (set LAB_DIR)"; exit 1; }

mkdir -p "$DST/src/lsl_pipeline" "$DST/data"
cp "$SRC/serve.py"              "$DST/serve.py"
cp "$SRC/src/lsl_pipeline/"*.py "$DST/src/lsl_pipeline/"
cp "$SRC/data/sample_input.csv" "$DST/data/"

echo "synced asset-service from $SRC ->"
find "$DST" -type f | sort
