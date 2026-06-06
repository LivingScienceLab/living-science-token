// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title LSL batch distribution (simulate-first, Ledger-signed)
/// @notice Transfers LSL from the signer to a list of recipients defined in a JSON config.
///         Mirrors the deploy's safety pattern: run it WITHOUT `--broadcast` first to simulate
///         against live chain state and print a full preview; only add `--broadcast --ledger`
///         once the preview looks right. The signer (`--sender`) is the source of every transfer.
///
/// Config file (default `distribution.json`, override with env `DISTRIBUTION_FILE`):
///   {
///     "recipients":   ["0xabc...", "0xdef..."],   // checksum addresses
///     "amountsTokens": [100000, 50000]             // WHOLE LSL (NOT wei); script multiplies by 1e18
///   }
/// Arrays must be equal length. Token address defaults to the deployed LSL; override with env
/// `LSL_TOKEN`.
///
/// DRY RUN (no signature, no broadcast — preview + simulate against mainnet state):
///   source .env
///   forge script script/Distribute.s.sol:Distribute --rpc-url mainnet --sender "$LEDGER_SENDER" -vvvv
///
/// REAL (Ledger-signed broadcast):
///   forge script script/Distribute.s.sol:Distribute --rpc-url mainnet \
///     --ledger --sender "$LEDGER_SENDER" --broadcast -vvvv
///
/// Or use the gated wrapper: `scripts/distribute.sh mainnet` (dry run, then asks before broadcast).
contract Distribute is Script {
    address constant DEFAULT_LSL = 0xe1Eb0f66a15b80f64CA252fbe0CA3087F74A9B08;

    function run() external {
        address token = vm.envOr("LSL_TOKEN", DEFAULT_LSL);
        string memory path = vm.envOr("DISTRIBUTION_FILE", string("distribution.json"));

        string memory json = vm.readFile(path);
        address[] memory to = vm.parseJsonAddressArray(json, ".recipients");
        uint256[] memory amtTokens = vm.parseJsonUintArray(json, ".amountsTokens");

        require(to.length == amtTokens.length, "DIST: recipients/amounts length mismatch");
        require(to.length > 0, "DIST: empty recipient list");

        address sender = msg.sender;
        IERC20 lsl = IERC20(token);
        uint256 startBal = lsl.balanceOf(sender);

        // --- Preview + validation (runs in both dry-run and real mode) ---
        console2.log("=== LSL distribution preview ===");
        console2.log("token            :", token);
        console2.log("from (signer)    :", sender);
        console2.log("signer balance   :", startBal / 1e18, "LSL");
        console2.log("recipients       :", to.length);

        uint256 totalWei;
        for (uint256 i = 0; i < to.length; i++) {
            require(to[i] != address(0), "DIST: zero-address recipient");
            require(to[i] != sender, "DIST: recipient equals sender");
            require(amtTokens[i] > 0, "DIST: zero amount");
            totalWei += amtTokens[i] * 1e18;
            console2.log("  ->", to[i]);
            console2.log("     amount     :", amtTokens[i], "LSL");
        }
        console2.log("total to send    :", totalWei / 1e18, "LSL");
        require(totalWei <= startBal, "DIST: total exceeds signer balance");
        console2.log("remaining after  :", (startBal - totalWei) / 1e18, "LSL");

        // --- Execute (simulated unless --broadcast is passed) ---
        vm.startBroadcast();
        for (uint256 i = 0; i < to.length; i++) {
            require(lsl.transfer(to[i], amtTokens[i] * 1e18), "DIST: transfer returned false");
        }
        vm.stopBroadcast();

        console2.log("=== distribution complete ===");
    }
}
