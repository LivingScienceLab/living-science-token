"""Wire the three stages together: ingest -> transform -> output."""

from __future__ import annotations

from pathlib import Path

from .ingest import ingest_csv
from .output import write_outputs
from .transform import transform


def run_pipeline(source: str | Path, out_dir: str | Path = "out") -> dict:
    """Run the full pipeline on a CSV source and return the output manifest."""
    raw = ingest_csv(source)
    records = transform(raw)
    manifest = write_outputs(records, source=str(source), out_dir=out_dir)
    return manifest
