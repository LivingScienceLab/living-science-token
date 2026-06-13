// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {LSLAccessGate} from "../src/LSLAccessGate.sol";

/// @notice Deploys the LSL Access Gate (spend-to-access) pointing at the live LSL token.
/// @dev    Owner and (default) treasury are the broadcasting account — for a Ledger deploy that
///         is your hardware-wallet address. No private keys are read from disk or env.
///
/// Config via env (all optional except none — sensible defaults shown):
///   LSL_TOKEN   token address          (default: mainnet LSL 0xe1Eb…9B08)
///   SINK        0 = Treasury, 1 = Burn (default: 0, Treasury)
///   TREASURY    spent-LSL destination  (default: the deployer; ignored when SINK=1)
///
/// Sepolia (rehearse first — deploy a mock token there or set LSL_TOKEN to the Sepolia LSL):
///   forge script script/DeployAccessGate.s.sol:DeployAccessGate \
///     --rpc-url sepolia --ledger --sender <YOUR_LEDGER_ADDRESS> \
///     --broadcast --verify -vvvv
///
/// Mainnet (only after Sepolia succeeds — spends real ETH):
///   forge script script/DeployAccessGate.s.sol:DeployAccessGate \
///     --rpc-url mainnet --ledger --sender <YOUR_LEDGER_ADDRESS> \
///     --broadcast --verify -vvvv
contract DeployAccessGate is Script {
    // Deployed, Etherscan-verified LSL token (same address on mainnet and Sepolia).
    address internal constant DEFAULT_TOKEN = 0xe1Eb0f66a15b80f64CA252fbe0CA3087F74A9B08;

    function run() external returns (LSLAccessGate gate) {
        address token = vm.envOr("LSL_TOKEN", DEFAULT_TOKEN);
        uint256 sinkRaw = vm.envOr("SINK", uint256(0));
        require(sinkRaw <= 1, "SINK must be 0 (Treasury) or 1 (Burn)");
        LSLAccessGate.SpentSink sink = LSLAccessGate.SpentSink(sinkRaw);

        address owner = msg.sender; // the broadcasting Ledger
        address treasury = sink == LSLAccessGate.SpentSink.Treasury ? vm.envOr("TREASURY", owner) : address(0);

        vm.startBroadcast();
        gate = new LSLAccessGate(token, sink, treasury, owner);
        vm.stopBroadcast();

        console2.log("LSLAccessGate deployed at:", address(gate));
        console2.log("Token:", token);
        console2.log("Owner:", owner);
        console2.log("Sink (0=Treasury,1=Burn):", sinkRaw);
        console2.log("Treasury:", treasury);
    }
}
