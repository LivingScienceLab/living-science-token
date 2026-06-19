"""Stage 2 — transform: clean and normalize raw rows into AI-ready records.

The "AI-ready" contract here is intentionally simple and explicit so it's easy
to reason about and extend:
  - strip whitespace on all string values
  - drop rows that are entirely empty
  - coerce numeric-looking fields to numbers
  - normalize keys to lower_snake_case

Replace/extend these rules as the real product's schema firms up.
"""

from __future__ import annotations

import re


def _norm_key(key: str) -> str:
    """lower_snake_case a column name: 'First Name' -> 'first_name'."""
    key = key.strip().lower()
    key = re.sub(r"[^\w]+", "_", key)
    return key.strip("_")


def _coerce(value: str):
    """Turn numeric-looking strings into int/float; leave others as stripped str."""
    v = value.strip()
    if v == "":
        return None
    try:
        return int(v)
    except ValueError:
        pass
    try:
        return float(v)
    except ValueError:
        return v


def transform(rows: list[dict]) -> list[dict]:
    """Normalize keys, coerce values, and drop fully-empty rows."""
    cleaned: list[dict] = []
    for row in rows:
        record = {_norm_key(k): _coerce(v) for k, v in row.items()}
        if any(val is not None for val in record.values()):
            cleaned.append(record)
    return cleaned
