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
// Production config (env, read from ../.env or the process env):
//   GATE_DOMAIN          SIWE domain binding — set to your real host (anti-phishing).
//   GATE_SESSION_SECRET  HMAC key for stateless session tokens — set a strong, stable value so
//                        sessions survive restarts and validate across instances. Unset → random
//                        per-boot secret (sessions drop on restart; a startup WARN is logged).
//   NONCE_RATE_MAX       /nonce requests allowed per IP per minute (default 30).
//   NETWORK              RPC alias/URL for chain reads (default mainnet).
// Sessions are stateless (signed tokens), so no session store is needed; the single-use nonce map
// is in-memory/per-instance — for multi-node, share it (e.g. Redis) and front /nonce with a WAF.
// Still TODO for a real deployment: point gate-upstreams.json at your real service, and terminate TLS
// (a reverse proxy / load balancer in front, or wrap this in https).
//
// Zero npm dependencies — Node http/crypto + child_process(cast). Reads config from ../.env.
import { createServer } from 'node:http';
import { execFileSync } from 'node:child_process';
import { readFileSync, existsSync } from 'node:fs';
import { randomBytes, createHmac, timingSafeEqual } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
// Config = optional .env file (dev) merged with process.env (containers/--env-file), env vars winning.
const envPath = join(ROOT, '.env');
const fileEnv = existsSync(envPath) ? Object.fromEntries(
  readFileSync(envPath, 'utf8')
    .split('\n').filter(l => l && !l.startsWith('#') && l.includes('='))
    .map(l => { const i = l.indexOf('='); return [l.slice(0, i).trim(), l.slice(i + 1).trim()]; })
) : {};
const env = { ...fileEnv, ...process.env };
const NET = env.NETWORK || 'mainnet';
const GATE = env.LSL_ACCESS_GATE_ADDRESS;
const KS = env.OPERATOR_KEYSTORE, PW = env.OPERATOR_KEYSTORE_PW;
const PORT = Number(env.PORT || 8088);
const CAST = env.CAST || `${process.env.HOME}/.config/.foundry/bin/cast`;
const DOMAIN = env.GATE_DOMAIN || `localhost:${PORT}`;            // SIWE domain binding (anti-phishing)
const NONCE_TTL_MS = 10 * 60 * 1000;                              // 10 min to complete login
const SESSION_TTL_MS = 60 * 60 * 1000;                            // 1 h session
const SESSION_SECRET = env.GATE_SESSION_SECRET;                   // HMAC key for stateless tokens
const RATE_MAX = Number(env.NONCE_RATE_MAX || 30);               // max /nonce requests per IP per window
const RATE_WINDOW_MS = 60 * 1000;
if (!GATE) { console.error('LSL_ACCESS_GATE_ADDRESS missing from .env'); process.exit(1); }

// Per-resource upstream config (gitignored — may hold API keys). Shape:
//   { "research-access": { "url": "https://api.example.org/x", "method": "GET",
//                          "headers": {"Authorization": "Bearer ..."}, "timeoutMs": 15000 } }
// A resource with no entry falls back to a labeled placeholder payload. Path defaults to
// <root>/gate-upstreams.json; override with GATE_UPSTREAMS_FILE (e.g. a mounted secret on Cloud Run).
const UPSTREAMS_FILE = env.GATE_UPSTREAMS_FILE || join(ROOT, 'gate-upstreams.json');
const UPSTREAMS = existsSync(UPSTREAMS_FILE)
  ? JSON.parse(readFileSync(UPSTREAMS_FILE, 'utf8')) : {};

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
const nonces = new Map();                                         // nonce -> expiry(ms) (single-use; in-memory)
// Stateless sessions: an HMAC-signed token {a:address, e:expiry}. Survives restarts (with a stable
// GATE_SESSION_SECRET) and needs no server-side session store, so it scales horizontally — set the
// SAME GATE_SESSION_SECRET on every node. (The `nonces` map is still per-instance; for multi-node use
// a shared store like Redis so a nonce issued by one node is single-use across all.)
const SECRET = SESSION_SECRET
  ? Buffer.from(SESSION_SECRET)
  : (console.warn('WARN: GATE_SESSION_SECRET unset — using a random per-boot secret (sessions drop on restart). Set it for persistence/multi-node.'), randomBytes(32));
function mintToken(address) {
  const payload = Buffer.from(JSON.stringify({ a: address, e: Date.now() + SESSION_TTL_MS })).toString('base64url');
  const sig = createHmac('sha256', SECRET).update(payload).digest('base64url');
  return `${payload}.${sig}`;
}
function tokenAddress(token) {                                    // -> address or null
  const [payload, sig] = String(token).split('.');
  if (!payload || !sig) return null;
  const want = createHmac('sha256', SECRET).update(payload).digest('base64url');
  const a = Buffer.from(sig), b = Buffer.from(want);
  if (a.length !== b.length || !timingSafeEqual(a, b)) return null;   // forged/edited token
  let p; try { p = JSON.parse(Buffer.from(payload, 'base64url').toString()); } catch { return null; }
  return p && Date.now() <= p.e ? p.a : null;                    // null if expired
}

function newNonce() {
  if (nonces.size > 10000) for (const [k, e] of nonces) if (Date.now() > e) nonces.delete(k); // opportunistic prune
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
  return { token: mintToken(address), address, expiresInSec: SESSION_TTL_MS / 1000 };
}
function authedAddress(req) {                                     // -> address or null
  const m = /^Bearer (.+)$/.exec(req.headers.authorization || '');
  return m ? tokenAddress(m[1]) : null;
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
// Simple fixed-window per-IP rate limiter for /nonce (in-memory; per-instance — front a shared
// limiter / WAF for multi-node). Caps anonymous nonce minting to blunt abuse.
const rate = new Map();                                          // ip -> { n, win }
function rateLimited(ip) {
  const now = Date.now(), r = rate.get(ip);
  if (!r || now - r.win > RATE_WINDOW_MS) { rate.set(ip, { n: 1, win: now }); return false; }
  return ++r.n > RATE_MAX;
}
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
    if (req.method === 'GET' && url.pathname === '/health') {      // for load-balancer / Cloud Run probes
      return send(res, 200, { status: 'ok', gate: GATE, net: NET, domain: DOMAIN });
    }
    if (req.method === 'GET' && url.pathname === '/nonce') {
      if (rateLimited(req.socket.remoteAddress || 'unknown')) throw httpErr(429, 'too many nonce requests; slow down');
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
  console.log(`  sessions: stateless HMAC${SESSION_SECRET ? ' (fixed secret)' : ' (random per-boot — set GATE_SESSION_SECRET)'} · /nonce rate-limit: ${RATE_MAX}/IP/min`);
  console.log(`  GET /nonce -> POST /login {message,signature} -> POST /serve?resource=.. (Bearer token)`);
  console.log(`  GET /check?user=0x..&resource=..  (public)`);
});
