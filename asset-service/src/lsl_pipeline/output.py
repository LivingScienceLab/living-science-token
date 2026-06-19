"""Stage 3 — output: write the AI-ready dataset plus a provenance manifest.

The manifest is the seed of the "IP asset" model: each dataset is emitted with
a record of where it came from, when it was built, how many rows, and a content
hash. That provenance is what you can later version, register, and gate behind
the LSL token.
"""

from __future__ import annotations

import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path


def _content_hash(records: list[dict]) -> str:
    """Deterministic SHA-256 over the canonical JSON of the records."""
    canonical = json.dumps(records, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def write_outputs(
    records: list[dict],
    source: str,
    out_dir: str | Path = "out",
    name: str | None = None,
) -> dict:
    """Write `<name>.dataset.json` and `<name>.manifest.json` into out_dir.

    Returns the manifest dict. `name` defaults to the source file's stem.
    """
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    stem = name or Path(source).stem

    dataset_path = out / f"{stem}.dataset.json"
    manifest_path = out / f"{stem}.manifest.json"

    manifest = {
        "name": stem,
        "source": str(source),
        "built_at": datetime.now(timezone.utc).isoformat(),
        "row_count": len(records),
        "content_sha256": _content_hash(records),
        "dataset_file": dataset_path.name,
        "pipeline_version": "0.1.0",
    }

    dataset_path.write_text(json.dumps(records, indent=2), encoding="utf-8")
    manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    return manifest
