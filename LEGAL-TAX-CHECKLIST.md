# Legal & Tax Considerations — Living Science Token (LSL)

> **⚠️ NOT LEGAL OR TAX ADVICE.** This is a checklist of *topics and questions to raise with a
> qualified securities attorney and a tax professional* licensed in your jurisdiction. It is a
> starting point for those conversations, not a substitute for them, and nothing here is a legal
> conclusion. Token regulation varies widely by country and changes frequently. Do not rely on
> this document for compliance. Engage professionals **before** distributing, selling, listing,
> or publicly marketing LSL.

Context: LSL is a fixed-supply (1,000,000), immutable, no-admin ERC-20 deployed to Ethereum
mainnet at `0xe1Eb0f66a15b80f64CA252fbe0CA3087F74A9B08`. As of this writing the **entire supply
is held on a single Ledger address and the token is not distributed, sold, or traded.** Most
legal/tax exposure is triggered by *what you do next* (distributing, selling, listing, marketing),
not by mere existence — which is exactly why this is worth sorting before any of that.

## 1. Securities classification (ask a securities attorney first)
- [ ] Could LSL be deemed a **security** in your jurisdiction? (In the US, discuss the *Howey* test
      with counsel: investment of money, common enterprise, expectation of profit from others'
      efforts. How you market and distribute it heavily affects this.)
- [ ] If distributed/sold, do you need a **registration or an exemption** (e.g. US Reg D / Reg S /
      Reg CF), and what are the conditions and filings for that exemption?
- [ ] Do **promotional statements** (website, social, whitepaper) imply profit expectation or a
      managerial role that could push it toward a security?
- [ ] Are there **resale restrictions / legends / lock-ups** you must impose on recipients?

## 2. Distribution mechanics (legal review of *how* you give/sell tokens)
- [ ] **Airdrop vs. sale vs. compensation vs. gift** — each has different legal and tax treatment.
      Which model applies to each recipient?
- [ ] **Recipient screening:** OFAC / sanctions lists, prohibited jurisdictions, and whether
      **KYC/AML** obligations attach to you as the distributor.
- [ ] If selling: **money transmitter / MSB** registration questions; payment handling.
- [ ] **Terms of distribution** / recipient agreements — who drafts and approves them?

## 3. Tax (ask a crypto-literate accountant)
- [ ] **At issuance:** does minting the full supply to yourself create a taxable event in your
      jurisdiction, or only on disposition? (Often the latter, but confirm.)
- [ ] **On distribution:** tax treatment when you transfer tokens out — gift tax, income to
      recipients, compensation/payroll if paid to contributors, etc.
- [ ] **Valuation:** how is LSL valued for tax when there's no market price yet? What establishes
      fair market value at the moment of each transfer?
- [ ] **Your cost basis** and the **recipients' basis**; holding-period / capital-gains
      implications on later sales.
- [ ] **Entity vs. personal:** is LSL held/issued by you personally or by Living Science Lab as an
      entity? This changes liability and tax. Should an entity hold it?
- [ ] **Record-keeping:** keep the deploy tx, every distribution tx, dates, FMV, and recipient
      details for tax filings. (The `broadcast/` artifacts + on-chain history are your audit trail.)

## 4. Jurisdiction & entity
- [ ] Which **country/state law** governs you and the project? Any multi-jurisdiction exposure if
      recipients are international?
- [ ] Is **Living Science Lab** a formed legal entity (LLC/corp/nonprofit)? Does the token's
      purpose (e.g. science/education/nonprofit) carry specific regulatory or charitable rules?
- [ ] **Liability:** personal exposure vs. entity shield for issuance and distribution.

## 5. Ongoing / operational
- [ ] **Disclosures & marketing rules** — what you can and can't claim publicly about LSL.
- [ ] **Consumer protection** obligations if the public can acquire it.
- [ ] If you later add **liquidity / list on a DEX or CEX**, re-run securities + tax analysis — that
      step materially changes the legal picture.
- [ ] **Multisig decision revisited:** custody/governance of the supply may have legal/insurance
      implications; reconsider single-key vs. Safe with counsel if the holdings become significant.

## Suggested order of operations
1. Engage a **securities attorney** and a **crypto-literate tax professional** in your jurisdiction.
2. Decide the **distribution model** (if any) with them *before* moving tokens.
3. Put **recipient agreements / disclosures** in place if advised.
4. Only then run a distribution (see `scripts/distribute.sh` — simulate-first, Ledger-signed).
5. Preserve **records** of every transfer for tax.
