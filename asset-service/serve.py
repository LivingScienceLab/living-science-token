#!/usr/bin/env python3
"""Living Science Lab — IP-asset HTTP service (the gated upstream).

This is the off-chain *upstream* that the LSL gatekeeper proxies to once a caller
has paid/authorized on-chain. The product (per the README) is the **AI-ready
dataset + provenance manifest** the pipeline emits — an "IP asset" that the LSL
token grants spend-to-access to. So this service does NOT take a caller's input;
it builds (or loads) the asset from Living Science Lab's OWN source data and
returns it. Interaction model: *retrieve the asset*, not *submit data*.

Topology (important):
    client ── SIWE+pay ──▶  LSL gatekeeper (public, :8088)  ──▶  THIS (loopback, :8090)
The gatekeeper enforces auth + payment and injects `X-LSL-User` / `X-LSL-Resource`.
This service therefore binds to **127.0.0.1 by default** — it must NOT be exposed
publicly; only the co-located gatekeeper should reach it. (Override with ASSET_HOST
only if you front it with your own auth.) Optionally set ASSET_SHARED_SECRET and
configure the gatekeeper to send a matching `X-Gate-Secret` header for defense in
depth.

Resource -> source mapping comes from `assets.json` if present, else a built-in
default (research-access -> data/sample_input.csv). Each gatekeeper resource id
maps to one source CSV; the asset is built once (run_pipeline) and cached.

Zero dependencies — Python standard library only. Reuses the pipeline in src/.

Endpoints:
    GET /health                         -> {"status":"ok",...}  (liveness)
    GET /asset[?resource=<id>]          -> {resource, served_to, manifest, dataset}
        The resource is taken from the X-LSL-Resource header (set by the gatekeeper)
        or the ?resource= query param; falls back to the single configured default.
"""

from __future__ import annotations

import json
import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse, parse_qs

ROOT = Path(__file__).parent
sys.path.insert(0, str(ROOT / "src"))

from lsl_pipeline.ingest import IngestError  # noqa: E402
from lsl_pipeline.pipeline import run_pipeline  # noqa: E402

HOST = os.environ.get("ASSET_HOST", "127.0.0.1")
PORT = int(os.environ.get("ASSET_PORT", "8090"))
OUT_DIR = ROOT / os.environ.get("ASSET_OUT_DIR", "out")
SHARED_SECRET = os.environ.get("ASSET_SHARED_SECRET")  # optional; matched against X-Gate-Secret

# Resource id (as configured on the LSLAccessGate) -> source CSV that builds its asset.
# Override / extend via assets.json next to this file.
DEFAULT_RESOURCES = {"research-access": "data/sample_input.csv"}


def load_resources() -> dict[str, str]:
    cfg = ROOT / "assets.json"
    if cfg.is_file():
        data = json.loads(cfg.read_text(encoding="utf-8"))
        # accept {"resource": "path.csv"} or {"resource": {"source": "path.csv"}}
        return {k: (v["source"] if isinstance(v, dict) else v) for k, v in data.items()}
    return dict(DEFAULT_RESOURCES)


RESOURCES = load_resources()
_CACHE: dict[str, dict] = {}  # resource -> {"manifest":..., "dataset":...}


def build_asset(resource: str) -> dict:
    """Return {manifest, dataset} for a resource, building + caching on first use."""
    if resource in _CACHE:
        return _CACHE[resource]
    source = RESOURCES.get(resource)
    if not source:
        raise KeyError(resource)
    src_path = (ROOT / source) if not os.path.isabs(source) else Path(source)
    # run_pipeline builds out/<stem>.dataset.json + <stem>.manifest.json and returns the manifest.
    manifest = run_pipeline(src_path, out_dir=OUT_DIR)
    dataset = json.loads((OUT_DIR / manifest["dataset_file"]).read_text(encoding="utf-8"))
    _CACHE[resource] = {"manifest": manifest, "dataset": dataset}
    return _CACHE[resource]


class Handler(BaseHTTPRequestHandler):
    server_version = "LSLAsset/0.1"

    def _send(self, code: int, obj: dict) -> None:
        body = json.dumps(obj, indent=2).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:  # noqa: N802 (stdlib naming)
        parsed = urlparse(self.path)
        if parsed.path == "/health":
            return self._send(200, {"status": "ok", "resources": sorted(RESOURCES)})
        if parsed.path != "/asset":
            return self._send(404, {"error": "GET /health | GET /asset[?resource=<id>]"})

        if SHARED_SECRET and self.headers.get("X-Gate-Secret") != SHARED_SECRET:
            return self._send(401, {"error": "missing or wrong X-Gate-Secret"})

        # Resource: gatekeeper's trusted X-LSL-Resource header wins; else ?resource=; else sole default.
        resource = self.headers.get("X-LSL-Resource") or (parse_qs(parsed.query).get("resource") or [None])[0]
        if not resource and len(RESOURCES) == 1:
            resource = next(iter(RESOURCES))
        if not resource:
            return self._send(400, {"error": "specify resource via X-LSL-Resource header or ?resource="})

        try:
            asset = build_asset(resource)
        except KeyError:
            return self._send(404, {"error": f"unknown resource '{resource}'", "known": sorted(RESOURCES)})
        except (IngestError, FileNotFoundError) as e:
            return self._send(500, {"error": f"asset build failed: {e}"})

        return self._send(200, {
            "resource": resource,
            "served_to": self.headers.get("X-LSL-User"),  # who paid, per the gatekeeper (informational)
            "manifest": asset["manifest"],
            "dataset": asset["dataset"],
        })

    def log_message(self, fmt: str, *args) -> None:  # quieter, structured-ish access log
        sys.stderr.write("[asset] %s - %s\n" % (self.address_string(), fmt % args))


def main() -> int:
    httpd = ThreadingHTTPServer((HOST, PORT), Handler)
    print(f"LSL asset service on http://{HOST}:{PORT}  resources={sorted(RESOURCES)}"
          + ("  (X-Gate-Secret required)" if SHARED_SECRET else ""))
    print(f"  GET /asset  -> dataset + manifest   |   bound to {HOST} (loopback = gatekeeper-only)")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        httpd.shutdown()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
