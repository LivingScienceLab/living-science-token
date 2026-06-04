// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

/// @title Living Science Token (LSL)
/// @notice Fixed-supply ERC-20 token.
///         - The entire supply is minted once, at deployment, to the deployer.
///         - There is no mint function and no owner/admin: supply can NEVER increase.
///         - Holders may burn their own tokens (ERC20Burnable), which only reduces supply.
///         - Supports gasless approvals via EIP-2612 permit (ERC20Permit).
/// @dev Built on audited OpenZeppelin v5 contracts. Decimals default to 18.
contract LivingScienceToken is ERC20, ERC20Burnable, ERC20Permit {
    /// @notice The full token supply, fixed at deployment: 1,000,000 tokens (with 18 decimals).
    uint256 public constant INITIAL_SUPPLY = 1_000_000 * 1e18;

    /// @param initialHolder The address that receives the entire initial supply.
    ///        For a Ledger deploy this is your Ledger address (the tx sender / `msg.sender`).
    constructor(address initialHolder) ERC20("Living Science Token", "LSL") ERC20Permit("Living Science Token") {
        require(initialHolder != address(0), "LSL: initial holder is zero address");
        _mint(initialHolder, INITIAL_SUPPLY);
    }
}
