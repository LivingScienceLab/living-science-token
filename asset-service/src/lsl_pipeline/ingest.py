"""Stage 1 — ingest: load raw data and validate its basic shape.

Today this reads a CSV into a list of dict rows. Kept deliberately small so the
contract (return List[dict]) is easy to extend to JSON / APIs / databases later.
"""

from __future__ import annotations

import csv
from pathlib import Path


class IngestError(Exception):
    """Raised when raw input can't be read or is structurally invalid."""


def ingest_csv(path: str | Path) -> list[dict]:
    """Load a CSV file into a list of row dicts.

    Validates that the file exists, is non-empty, and has a header row.
    Returns one dict per data row, keyed by column name.
    """
    p = Path(path)
    if not p.is_file():
        raise IngestError(f"input file not found: {p}")

    with p.open(newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        if reader.fieldnames is None:
            raise IngestError(f"no header row found in {p}")
        rows = [dict(r) for r in reader]

    if not rows:
        raise IngestError(f"no data rows found in {p}")

    return rows
