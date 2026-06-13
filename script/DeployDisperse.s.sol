// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {LSLDisperse} from "../src/LSLDisperse.sol";

/// @notice Deploys LSLDisperse, the stateless batch-transfer helper used to distribute LSL in a
///         single transaction (caller approves it for the total, then calls `disperse`).
/// @dev    The helper holds no funds and has no owner, so the deployer gets no special powers —
///         the only purpose of signing this is to put the helper on-chain. Deploy it once.
///
/// Sepolia (rehearse first):
///   forge script script/DeployDisperse.s.sol:DeployDisperse \
///     --rpc-url sepolia --ledger --sender <YOUR_LEDGER_ADDRESS> \
///     --broadcast --verify -vvvv
///
/// Mainnet (only after Sepolia succeeds — spends real ETH):
///   forge script script/DeployDisperse.s.sol:DeployDisperse \
///     --rpc-url mainnet --ledger --sender <YOUR_LEDGER_ADDRESS> \
///     --broadcast --verify -vvvv
contract DeployDisperse is Script {
    function run() external returns (LSLDisperse disperser) {
        vm.startBroadcast();
        disperser = new LSLDisperse();
        vm.stopBroadcast();

        console2.log("LSLDisperse deployed at:", address(disperser));
    }
}
