# Living Science Token (LSL)

A fixed-supply ERC-20 token built on [OpenZeppelin v5](https://github.com/OpenZeppelin/openzeppelin-contracts) and [Foundry](https://book.getfoundry.sh/).

## Token design

| Property        | Value                                                        |
|-----------------|-------------------------------------------------------------|
| Name            | Living Science Token                                         |
| Symbol          | LSL                                                          |
| Decimals        | 18                                                           |
| Total supply    | 1,000,000 LSL (minted once, at deployment, to the deployer) |
| Mintable?       | **No** — there is no mint function; supply can never increase |
| Burnable?       | Yes — holders may burn their own tokens (supply only goes down) |
| Permit (EIP-2612)? | Yes — gasless approvals via signature                    |
| Owner / admin?  | **None** — no privileged role, nothing to pause or freeze    |

The contract is immutable: once deployed, no one (including you) can mint new tokens,
freeze transfers, or change anything. This is the most trustworthy configuration for a
fungible token. See [`src/LivingScienceToken.sol`](src/LivingScienceToken.sol).

## Project layout

```
src/LivingScienceToken.sol     # the token contract
test/LivingScienceToken.t.sol  # full test suite (unit + fuzz)
script/Deploy.s.sol            # deployment script (Ledger-signed)
foundry.toml                   # solc 0.8.24, optimizer, RPC + Etherscan config
.env.example                   # template for your Alchemy / Etherscan keys
.github/workflows/test.yml     # CI: builds + tests on every push/PR
```

## Setup

1. Install [Foundry](https://book.getfoundry.sh/getting-started/installation):
   ```bash
   curl -L https://foundry.paradigm.xyz | bash && foundryup
   ```
2. Build and test:
   ```bash
   forge build
   forge test -vvv
   ```
3. Configure secrets:
   ```bash
   cp .env.example .env
   # edit .env: add your Alchemy RPC URLs and Etherscan key
   source .env   # or use a tool like direnv
   ```
   `.env` is gitignored and must never be committed.

## Deployment

Signing is done **on your Ledger hardware wallet** — no private key ever touches disk,
env, or this machine. Make sure your Ledger is:
- plugged in and unlocked,
- running the **Ethereum** app,
- with **"Blind signing" / "Contract data" enabled** (Settings → in the Ethereum app),
  which is required to sign a contract-deployment transaction.

The account that signs the broadcast receives the entire 1,000,000 LSL supply.

### Step 1 — Sepolia testnet first (free, mandatory dry run)

Get free Sepolia ETH from a faucet (e.g. https://sepoliafaucet.com) to your Ledger address, then:

```bash
source .env
forge script script/Deploy.s.sol:Deploy \
  --rpc-url sepolia \
  --ledger --sender "$LEDGER_SENDER" \
  --broadcast --verify -vvvv
```

Confirm the transaction **on the Ledger screen**. After it lands, check the contract on
https://sepolia.etherscan.io and verify name, symbol, supply, and your balance are correct.

### Step 2 — Ethereum mainnet (spends real ETH — irreversible)

Only after Sepolia looks perfect. The code is identical; only the network changes:

```bash
source .env
forge script script/Deploy.s.sol:Deploy \
  --rpc-url mainnet \
  --ledger --sender "$LEDGER_SENDER" \
  --broadcast --verify -vvvv
```

> ⚠️ This deploys a permanent contract to Ethereum mainnet and costs real ETH in gas.
> A token deploy is typically ~1.0–1.5M gas; cost = gas × gas price. Check current gas at
> https://etherscan.io/gastracker before broadcasting. There is no undo.

### Dry run without broadcasting

To simulate (no signing, no cost), omit `--broadcast`:

```bash
forge script script/Deploy.s.sol:Deploy --rpc-url sepolia --sender "$LEDGER_SENDER"
```

## Source verification

Passing `--verify` with `ETHERSCAN_API_KEY` set publishes your source to Etherscan so
anyone can read and trust the deployed bytecode. If verification fails during deploy, you
can run it separately afterward with `forge verify-contract`.

## License

MIT
