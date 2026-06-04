# Pre-Mainnet Deploy Checklist — Living Science Token (LSL)

Work top to bottom. Do **not** skip the Sepolia section. Mainnet is permanent and costs real ETH.

## 0. Code quality (DONE ✅)
- [x] Contract built on audited OpenZeppelin v5.6.1
- [x] Slither static analysis: 0 findings
- [x] Independent security review: no mint / no owner / no pause / no upgrade — supply only decreases
- [x] 22 tests passing (incl. permit reverts, replay, zero-address, events, domain separator)
- [x] CI pinned to stable Foundry

## 1. Accounts & secrets
- [ ] `gh auth login` complete (for GitHub push)
- [ ] `gcloud auth login` complete (for CSR mirror)
- [ ] CSR repo URL on hand: `https://source.developers.google.com/p/PROJECT/r/REPO`
- [ ] `.env` created from `.env.example` with:
  - [ ] `SEPOLIA_RPC_URL` (Alchemy)
  - [ ] `MAINNET_RPC_URL` (Alchemy)
  - [ ] `ETHERSCAN_API_KEY` (current V2-era key, so `--verify` works)
  - [ ] `LEDGER_SENDER` = your Ledger Ethereum address
- [ ] Confirmed `.env` is gitignored (it is) and never committed

## 2. Ledger readiness 🔑 (highest stakes — all 1,000,000 LSL lands here)
- [ ] **24-word seed phrase backed up offline** (steel/paper, not a photo, not cloud)
- [ ] Decided: supply stays on single Ledger address, OR will move to a multisig (e.g. Safe)
- [ ] Ledger firmware + Ethereum app up to date
- [ ] Ethereum app: **Blind signing / Contract data = ENABLED** (required for contract deploy)
- [ ] You can see and confirm the deploy address matches `LEDGER_SENDER`

## 3. Sepolia dry run (MANDATORY)
- [ ] Funded Ledger address with free Sepolia ETH (faucet)
- [ ] Deployed:
      ```
      source .env
      forge script script/Deploy.s.sol:Deploy \
        --rpc-url sepolia --ledger --sender "$LEDGER_SENDER" \
        --broadcast --verify -vvvv
      ```
- [ ] Confirmed the tx on the Ledger screen
- [ ] Contract shows on https://sepolia.etherscan.io with correct name/symbol/supply
- [ ] Source **verified** on Etherscan (green check)
- [ ] Imported token into MetaMask using the contract address
- [ ] Test transfer works
- [ ] Test burn works
- [ ] `balanceOf(LEDGER_SENDER)` == 1,000,000 * 1e18

## 4. Mainnet deploy (only after every box above is checked)
- [ ] Enough ETH on Ledger for gas (check https://etherscan.io/gastracker; ~1.0–1.5M gas)
- [ ] Deployed:
      ```
      source .env
      forge script script/Deploy.s.sol:Deploy \
        --rpc-url mainnet --ledger --sender "$LEDGER_SENDER" \
        --broadcast --verify -vvvv
      ```
- [ ] Verified gas total on the Ledger BEFORE approving
- [ ] Contract verified on https://etherscan.io
- [ ] Recorded the deployed contract address: `0x____________________`

## 5. Post-deploy
- [ ] Saved deployment artifact (`broadcast/` folder) and committed it
- [ ] Distribution plan executed/scheduled (liquidity / transfers / vesting / multisig move)
- [ ] (If applicable) checked legal/tax/regulatory obligations for your jurisdiction
