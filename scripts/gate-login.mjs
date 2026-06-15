#!/usr/bin/env node
// Reference SIWE client for the LSL gatekeeper: fetch a nonce, build + sign an EIP-4361 message,
// log in, and (optionally) call /serve. Demonstrates the proof-of-control flow end-to-end.
//
// Usage:
//   node scripts/gate-login.mjs --url http://localhost:8088 --key 0x<privkey> [--serve <resource>]
//   node scripts/gate-login.mjs --url http://localhost:8088 --ledger 1        [--serve <resource>]
//     (--ledger N signs with m/44'/60'/0'/0/N on a connected Ledger)
//
// Env: GATE_DOMAIN must match the gatekeeper's (default localhost:<port-from-url>).
import { execFileSync } from 'node:child_process';

const CAST = process.env.CAST || `${process.env.HOME}/.config/.foundry/bin/cast`;
const args = Object.fromEntries(process.argv.slice(2).reduce((a, v, i, arr) =>
  v.startsWith('--') ? [...a, [v.slice(2), arr[i + 1] && !arr[i + 1].startsWith('--') ? arr[i + 1] : true]] : a, []));
const URL_ = args.url || 'http://localhost:8088';
const DOMAIN = process.env.GATE_DOMAIN || new URL(URL_).host;

// Build the cast signer args for either a raw key or a Ledger derivation index.
function signerArgs() {
  if (args.key) return ['--private-key', String(args.key)];
  if (args.ledger !== undefined) return ['--ledger', '--mnemonic-derivation-path', `m/44'/60'/0'/0/${args.ledger}`];
  throw new Error('pass --key 0x.. or --ledger N');
}
const cast = (...a) => execFileSync(CAST, a, { encoding: 'utf8' }).trim();
const jget = async p => (await fetch(URL_ + p)).json();
const jpost = async (p, body, headers = {}) =>
  (await fetch(URL_ + p, { method: 'POST', headers: { 'content-type': 'application/json', ...headers }, body: JSON.stringify(body) }));

const SIG = signerArgs();
const address = cast('wallet', 'address', ...SIG);
console.log('signer address :', address);

const { nonce } = await jget('/nonce');
console.log('nonce          :', nonce);

const issued = new Date().toISOString();
const expires = new Date(Date.now() + 9 * 60 * 1000).toISOString();
const message =
`${DOMAIN} wants you to sign in with your Ethereum account:
${address}

Sign in to the LSL Access Gate.

URI: ${URL_}
Version: 1
Chain ID: 1
Nonce: ${nonce}
Issued At: ${issued}
Expiration Time: ${expires}`;

console.log('signing SIWE message' + (args.ledger !== undefined ? ' — CONFIRM ON LEDGER…' : '…'));
const signature = cast('wallet', 'sign', ...SIG, message);

const r = await jpost('/login', { message, signature });
const body = await r.json();
if (!r.ok) { console.error('login FAILED:', body); process.exit(1); }
console.log('login OK       : token', body.token.slice(0, 12) + '…  (expires in', body.expiresInSec + 's)');

if (args.serve) {
  const sr = await jpost(`/serve?resource=${encodeURIComponent(args.serve)}`, {}, { authorization: `Bearer ${body.token}` });
  console.log(`/serve ${args.serve} -> ${sr.status}`);
  console.log(JSON.stringify(await sr.json(), null, 2));
}
