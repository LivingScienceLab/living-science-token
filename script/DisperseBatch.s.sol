// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {LSLDisperse} from "../src/LSLDisperse.sol";

/// @title LSL batch distribution via LSLDisperse (single-batch, 2 Ledger signatures)
/// @notice Reads the SAME `distribution.json` as `Distribute.s.sol`, but moves the tokens with
///         one `approve` + one `LSLDisperse.disperse` instead of N individual transfers. The
///         signer (`--sender`) is the source of every token; the deployed `LSLDisperse` helper
///         (env `LSL_DISPERSE`) is the spender that fans them out atomically.
///
/// Why this exists: the sequential `Distribute.s.sol` costs one base-tx (21k gas) PER recipient
/// and asks for one Ledger confirmation per recipient. This path pays the base-tx cost twice
/// total and asks for exactly two confirmations, regardless of recipient count — and the
/// disperse is atomic, so a mid-batch failure can never half-distribute or double-send on retry.
///
/// Config file (default `distribution.json`, override env `DISTRIBUTION_FILE`):
///   {
///     "recipients":   ["0xabc...", "0xdef..."],   // checksum addresses
///     "amountsTokens": [100000, 50000]             // WHOLE LSL (NOT wei); script multiplies by 1e18
///   }
/// Arrays must be equal length. Token defaults to the deployed LSL; override env `LSL_TOKEN`.
/// The deployed disperser address is REQUIRED via env `LSL_DISPERSE` (deploy it once with
/// `script/DeployDisperse.s.sol`).
///
/// DRY RUN (no signature — simulates BOTH the approve and the disperse against live chain state):
///   source .env
///   LSL_DISPERSE=<disperser> forge script script/DisperseBatch.s.sol:DisperseBatch \
///     --rpc-url mainnet --sender "$LEDGER_SENDER" -vvvv
///
/// REAL (Ledger-signed broadcast — two transactions; use --slow so approve mines before disperse):
///   LSL_DISPERSE=<disperser> forge script script/DisperseBatch.s.sol:DisperseBatch \
///     --rpc-url mainnet --ledger --sender "$LEDGER_SENDER" --broadcast --slow -vvvv
///
/// Or use the gated wrapper: `scripts/disperse.sh mainnet` (dry run, then asks before broadcast).
contract DisperseBatch is Script {
    address constant DEFAULT_LSL = 0xe1Eb0f66a15b80f64CA252fbe0CA3087F74A9B08;

    function run() external {
        address token = vm.envOr("LSL_TOKEN", DEFAULT_LSL);
        address disperser = vm.envAddress("LSL_DISPERSE");
        string memory path = vm.envOr("DISTRIBUTION_FILE", string("distribution.json"));

        string memory json = vm.readFile(path);
        address[] memory to = vm.parseJsonAddressArray(json, ".recipients");
        uint256[] memory amtTokens = vm.parseJsonUintArray(json, ".amountsTokens");

        require(disperser != address(0), "DIST: LSL_DISPERSE is zero");
        require(to.length == amtTokens.length, "DIST: recipients/amounts length mismatch");
        require(to.length > 0, "DIST: empty recipient list");

        address sender = msg.sender;
        IERC20 lsl = IERC20(token);
        uint256 startBal = lsl.balanceOf(sender);

        // --- Preview + validation (runs in both dry-run and real mode) ---
        console2.log("=== LSL disperse preview ===");
        console2.log("token            :", token);
        console2.log("disperser        :", disperser);
        console2.log("from (signer)    :", sender);
        console2.log("signer balance   :", startBal / 1e18, "LSL");
        console2.log("recipients       :", to.length);

        // Build the wei amounts and total; validate every entry.
        uint256[] memory amtWei = new uint256[](to.length);
        uint256 totalWei;
        for (uint256 i = 0; i < to.length; i++) {
            require(to[i] != address(0), "DIST: zero-address recipient");
            require(to[i] != sender, "DIST: recipient equals sender");
            require(to[i] != disperser, "DIST: recipient equals disperser");
            require(amtTokens[i] > 0, "DIST: zero amount");
            // Reject duplicate recipients (a likely copy-paste error on an irreversible transfer).
            for (uint256 j = 0; j < i; j++) {
                require(to[i] != to[j], "DIST: duplicate recipient");
            }
            amtWei[i] = amtTokens[i] * 1e18;
            totalWei += amtWei[i];
            console2.log("  ->", to[i]);
            console2.log("     amount     :", amtTokens[i], "LSL");
        }
        console2.log("total to send    :", totalWei / 1e18, "LSL");
        require(totalWei <= startBal, "DIST: total exceeds signer balance");
        console2.log("remaining after  :", (startBal - totalWei) / 1e18, "LSL");
        console2.log("plan             : tx1 approve(disperser, total), tx2 disperse(...)");

        // --- Execute (simulated unless --broadcast is passed) ---
        // Two broadcast calls => two transactions => two Ledger confirmations, for any N.
        // Approve EXACTLY the total so no allowance lingers after the batch.
        vm.startBroadcast();
        require(lsl.approve(disperser, totalWei), "DIST: approve returned false");
        LSLDisperse(disperser).disperse(lsl, to, amtWei);
        vm.stopBroadcast();

        console2.log("=== disperse complete ===");
    }
}
