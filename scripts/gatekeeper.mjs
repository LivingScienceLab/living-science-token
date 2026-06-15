#!/usr/bin/env node
// LSL Access Gate — REFERENCE off-chain gatekeeper with SIWE proof-of-control (a TEMPLATE).
//
// The LSLAccessGate contract is only the on-chain record of payment + entitlement; per its own
// docs it "cannot gate the off-chain service by itself." THIS process is the missing half: it
// authenticates the caller, reads the gate, and decides whether to serve your real service/IP.
//
// AUTH (SIWE / EIP-4361 — prevents anyone from spending or riding another user's access):
//   GET  /nonce                       -> { nonce }   single-use, short-lived
//   POST /login  {message,signature}  -> { token }   verifies the SIWE message was signed by the
//                                                     address it claims; binds a session to it
// ACCESS (require  Authorization: Bearer <token>;  the user is the SESSION address, never a param):
//   POST /serve?resource=<name>       -> 200 + content if access is valid, else 402
//        - Subscription: allow while live (a free view read; no tx, no gas).
//        - PerUse:       redeem ONE credit via the operator key (on-chain consume()) and allow.
//   GET  /check?user=0x..&resource=<name>  -> { allow, model, credits, expiry }   PUBLIC read-only
//        (on-chain state is public; no content served and no credit burned, so no auth needed)
//
// To make this real: replace serveContent() with your actual service, set GATE_DOMAIN to your
// host, put it behind TLS, and persist nonces/sessions (this template keeps them in memory).
//
// Zero npm dependencies — Node http/crypto + child_process(cast). Reads config from ../.env.
import { createServer } from 'node:http';
import { execFileSync } from 'node:child_process';
import { readFileSync, existsSync } from 'node:fs';
import { randomBytes } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const env = Object.fromEntries(
  readFileSync(join(ROOT, '.env'), 'utf8')
    .split('\n').filter(l => l && !l.startsWith('#') && l.includes('='))
    .map(l => { const i = l.indexOf('='); return [l.slice(0, i).trim(), l.slice(i + 1).trim()]; })
);
const NET = process.env.NETWORK || 'mainnet';
const GATE = env.LSL_ACCESS_GATE_ADDRESS;
const KS = env.OPERATOR_KEYSTORE, PW = env.OPERATOR_KEYSTORE_PW;
const PORT = Number(process.env.PORT || 8088);
const CAST = process.env.CAST || `${process.env.HOME}/.config/.foundry/bin/cast`;
const DOMAIN = process.env.GATE_DOMAIN || `localhost:${PORT}`;     // SIWE domain binding (anti-phishing)
const NONCE_TTL_MS = 10 * 60 * 1000;                              // 10 min to complete login
const SESSION_TTL_MS = 60 * 60 * 1000;                            // 1 h session
if (!GATE) { console.error('LSL_ACCESS_GATE_ADDRESS missing from .env'); process.exit(1); }

// Per-resource upstream config (gitignored — may hold API keys). Shape:
//   { "research-access": { "url": "https://api.example.org/x", "method": "GET",
//                          "headers": {"Authorization": "Bearer ..."}, "timeoutMs": 15000 } }
// A resource with no entry falls back to a labeled placeholder payload.
const UPSTREAMS = existsSync(join(ROOT, 'gate-upstreams.json'))
  ? JSON.parse(readFileSync(join(ROOT, 'gate-upstreams.json'), 'utf8')) : {};

/* ---------------------------- on-chain reads ---------------------------- */
// Right-pad a <=31-char string to bytes32 — matches `cast format-bytes32-string` (NOT keccak256).
function rid(s) {
  const b = Buffer.from(s, 'utf8');
  if (b.length > 31) throw new Error(`resource id "${s}" exceeds 31 bytes`);
  const out = Buffer.alloc(32); b.copy(out);
  return '0x' + out.toString('hex');
}
const strip = s => String(s).trim().split(' ')[0];               // drop cast's "[5e19]" annotation
const cast = (...a) => execFileSync(CAST, a, { encoding: 'utf8' }).trim();
const call = (sig, ...args) => cast('call', GATE, sig, ...args, '--rpc-url', NET);
const resourceModel = id => Number(strip(call('resources(bytes32)(uint128,uint64,uint8,bool)', id).split('\n')[2]));
function snapshot(user, id) {
  return {
    allow: call('hasAccess(address,bytes32)(bool)', user, id) === 'true',
    model: resourceModel(id) === 0 ? 'PerUse' : 'Subscription',
    credits: strip(call('credits(address,bytes32)(uint256)', user, id)),
    expiry: strip(call('accessExpiry(address,bytes32)(uint64)', user, id)),
  };
}
function consumeOne(user, id) {                                   // operator redeems 1 PerUse credit
  if (!KS || !PW) throw new Error('operator keystore/password not configured');
  return JSON.parse(cast('send', GATE, 'consume(address,bytes32,uint256)', user, id, '1',
    '--rpc-url', NET, '--keystore', KS, '--password', PW, '--json'));
}

/* ------------------------------ SIWE auth ------------------------------- */
const nonces = new Map();                                         // nonce -> expiry(ms)
const sessions = new Map();                                       // token -> { address, expiry }

function newNonce() {
  const n = randomBytes(16).toString('hex');
  nonces.set(n, Date.now() + NONCE_TTL_MS);
  return n;
}
// Verify an EIP-191 personal_sign over `message` was produced by `address`.
function verifySig(address, message, signature) {
  try { execFileSync(CAST, ['wallet', 'verify', '--address', address, message, signature], { stdio: 'pipe' }); return true; }
  catch { return false; }
}
// Minimal EIP-4361 parser — pulls the fields we enforce. (A real deployment should use a vetted
// SIWE library; this is a dependency-free reference.)
function parseSiwe(msg) {
  const domain = (msg.match(/^(.*?) wants you to sign in with your Ethereum account:$/m) || [])[1];
  const address = (msg.match(/^(0x[0-9a-fA-F]{40})$/m) || [])[1];
  const nonce = (msg.match(/^Nonce: (.+)$/m) || [])[1];
  const exp = (msg.match(/^Expiration Time: (.+)$/m) || [])[1];
  return { domain, address, nonce, expiration: exp };
}
function login(message, signature) {
  const { domain, address, nonce, expiration } = parseSiwe(message);
  if (!address || !nonce || !domain) throw httpErr(400, 'malformed SIWE message');
  if (domain !== DOMAIN) throw httpErr(401, `wrong domain (expected ${DOMAIN})`);
  const exp = nonces.get(nonce);
  if (!exp) throw httpErr(401, 'unknown or already-used nonce');
  nonces.delete(nonce);                                          // single-use: consume immediately
  if (Date.now() > exp) throw httpErr(401, 'nonce expired');
  if (expiration && Date.now() > Date.parse(expiration)) throw httpErr(401, 'SIWE message expired');
  if (!verifySig(address, message, signature)) throw httpErr(401, 'signature does not match address');
  const token = randomBytes(24).toString('hex');
  sessions.set(token, { address, expiry: Date.now() + SESSION_TTL_MS });
  return { token, address, expiresInSec: SESSION_TTL_MS / 1000 };
}
function authedAddress(req) {                                     // -> address or null
  const m = /^Bearer (.+)$/.exec(req.headers.authorization || '');
  if (!m) return null;
  const s = sessions.get(m[1]);
  if (!s) return null;
  if (Date.now() > s.expiry) { sessions.delete(m[1]); return null; }
  return s.address;
}

/* ------------------------------- service -------------------------------- */
// Deliver gated content for an authorized user. If `gate-upstreams.json` configures an upstream
// for this resource, reverse-proxy to it — injecting the upstream's own auth plus an `X-LSL-User`
// header so it knows who paid — and relay the response verbatim (binary-safe). With no upstream
// configured it returns a labeled placeholder so the template still runs.
// The upstream URL comes from trusted server config, NOT user input, so there is no SSRF surface.
async function deliver(user, resource) {
  const up = UPSTREAMS[resource];
  if (!up || !up.url) {
    return { status: 200, contentType: 'application/json', body: Buffer.from(JSON.stringify(
      { ok: true, resource, served_to: user,
        note: 'No upstream configured — add this resource to gate-upstreams.json to proxy your real service.' }, null, 2)) };
  }
  const r = await fetch(up.url, {
    method: up.method || 'GET',
    headers: { 'X-LSL-User': user, 'X-LSL-Resource': resource, ...(up.headers || {}) },
    // Optional fixed request body (e.g. a JSON-RPC call). Object → JSON; string sent as-is.
    ...(up.body !== undefined ? { body: typeof up.body === 'string' ? up.body : JSON.stringify(up.body) } : {}),
    signal: AbortSignal.timeout(Number(up.timeoutMs) || 15000),
  });
  return { status: r.status, contentType: r.headers.get('content-type') || 'application/octet-stream',
    body: Buffer.from(await r.arrayBuffer()) };
}

/* -------------------------------- http ---------------------------------- */
const isAddr = s => /^0x[0-9a-fA-F]{40}$/.test(s || '');
const httpErr = (code, msg) => Object.assign(new Error(msg), { code });
const send = (res, code, obj) => { res.writeHead(code, { 'content-type': 'application/json' }); res.end(JSON.stringify(obj, null, 2)); };
const sendRaw = (res, code, contentType, buf, extra = {}) => { res.writeHead(code, { 'content-type': contentType, ...extra }); res.end(buf); };
const readBody = req => new Promise((resolve, reject) => {
  let d = ''; req.on('data', c => { d += c; if (d.length > 1e6) req.destroy(); });
  req.on('end', () => resolve(d)); req.on('error', reject);
});

createServer(async (req, res) => {
  const url = new URL(req.url, `http://localhost:${PORT}`);
  try {
    if (req.method === 'GET' && url.pathname === '/nonce') {
      return send(res, 200, { nonce: newNonce(), domain: DOMAIN, ttlSec: NONCE_TTL_MS / 1000 });
    }
    if (req.method === 'POST' && url.pathname === '/login') {
      const { message, signature } = JSON.parse((await readBody(req)) || '{}');
      if (!message || !signature) throw httpErr(400, 'POST {message, signature}');
      return send(res, 200, login(message, signature));
    }
    if (req.method === 'GET' && url.pathname === '/check') {       // PUBLIC: read-only on-chain state
      const user = url.searchParams.get('user'), resource = url.searchParams.get('resource');
      if (!isAddr(user) || !resource) throw httpErr(400, 'pass ?user=0x40hex&resource=<name>');
      return send(res, 200, { user, resource, ...snapshot(user, rid(resource)) });
    }
    if (req.method === 'POST' && url.pathname === '/serve') {      // AUTH REQUIRED
      const user = authedAddress(req);
      if (!user) throw httpErr(401, 'authenticate first: GET /nonce -> POST /login -> Bearer token');
      const resource = url.searchParams.get('resource');
      if (!resource) throw httpErr(400, 'pass ?resource=<name>');
      const id = rid(resource), s = snapshot(user, id);
      if (!s.allow) return send(res, 402, { error: 'no access', user, resource, ...s });
      const out = await deliver(user, resource);                  // proxy to upstream (or placeholder)
      if (out.status >= 400) {                                    // upstream failed → don't burn a credit
        return send(res, 502, { error: 'upstream error', upstreamStatus: out.status, user, resource });
      }
      let hdr = {};
      if (s.model === 'PerUse') {                                 // burn one credit ONLY after success
        const tx = consumeOne(user, id);
        hdr = { 'X-LSL-Consumed': '1', 'X-LSL-Consume-Tx': tx.transactionHash };
      }
      return sendRaw(res, 200, out.contentType, out.body, hdr);   // relay upstream response verbatim
    }
    throw httpErr(404, 'GET /nonce | POST /login | GET /check | POST /serve');
  } catch (e) {
    return send(res, e.code && e.code < 600 ? e.code : 500, { error: String(e.message || e) });
  }
}).listen(PORT, () => {
  console.log(`LSL gatekeeper (REFERENCE, SIWE) on :${PORT}  gate=${GATE}  net=${NET}  domain=${DOMAIN}`);
  console.log(`  GET /nonce -> POST /login {message,signature} -> POST /serve?resource=.. (Bearer token)`);
  console.log(`  GET /check?user=0x..&resource=..  (public)`);
});
