// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {LivingScienceToken} from "../src/LivingScienceToken.sol";

/// @notice Deploys LivingScienceToken, minting the full supply to the deployer (msg.sender).
/// @dev    The deployer is whatever address signs the broadcast — for a Ledger deploy this is
///         your hardware-wallet address. No private keys are ever read from disk or env.
///
/// Sepolia (test first!):
///   forge script script/Deploy.s.sol:Deploy \
///     --rpc-url sepolia --ledger --sender <YOUR_LEDGER_ADDRESS> \
///     --broadcast --verify -vvvv
///
/// Mainnet (only after Sepolia succeeds — spends real ETH):
///   forge script script/Deploy.s.sol:Deploy \
///     --rpc-url mainnet --ledger --sender <YOUR_LEDGER_ADDRESS> \
///     --broadcast --verify -vvvv
contract Deploy is Script {
    function run() external returns (LivingScienceToken token) {
        // The full supply is minted to the broadcasting account (your Ledger address).
        address initialHolder = msg.sender;

        vm.startBroadcast();
        token = new LivingScienceToken(initialHolder);
        vm.stopBroadcast();

        console2.log("LivingScienceToken deployed at:", address(token));
        console2.log("Initial holder (full supply):", initialHolder);
        console2.log("Total supply (wei):", token.totalSupply());
    }
}
