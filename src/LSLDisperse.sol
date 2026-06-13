// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title LSLDisperse — stateless batch-transfer helper
/// @notice Moves an ERC-20 from the caller to many recipients in a single transaction via
///         `transferFrom`. The caller must first approve this contract for (at least) the sum
///         of `amounts`. Written to distribute Living Science Token (LSL), but works with any
///         standard ERC-20.
/// @dev Deliberately minimal and trustless, mirroring LSL's own design:
///      - No owner, no admin, no privileged roles, no upgradeability.
///      - No storage and no token custody — funds move straight from the caller to each
///        recipient, so nothing can ever be stuck in, or pulled out of, this contract.
///      - Atomic: any failed leg reverts the whole batch, so re-running after a failure can
///        never double-send to recipients that already received their share.
///      Each leg emits the token's own `Transfer` event; that is the on-chain audit trail.
contract LSLDisperse {
    /// @notice `recipients` and `amounts` had different lengths.
    error LengthMismatch(uint256 recipients, uint256 amounts);
    /// @notice The batch was empty.
    error EmptyBatch();
    /// @notice `token.transferFrom` returned false (a non-reverting failure) for `recipient`.
    error TransferFailed(address recipient, uint256 amount);

    /// @notice Transfer `amounts[i]` of `token` from the caller to `recipients[i]`, for all i.
    /// @dev The caller must have approved this contract for at least the sum of `amounts`.
    ///      Reverts — rolling back the entire batch — on length mismatch, empty input, or any
    ///      failed leg (including insufficient balance/allowance, which the token enforces).
    /// @param token      The ERC-20 to distribute.
    /// @param recipients Destination addresses; must be the same length as `amounts`.
    /// @param amounts    Per-recipient amounts in token base units (wei), aligned with `recipients`.
    function disperse(IERC20 token, address[] calldata recipients, uint256[] calldata amounts) external {
        uint256 n = recipients.length;
        if (n != amounts.length) revert LengthMismatch(n, amounts.length);
        if (n == 0) revert EmptyBatch();
        for (uint256 i = 0; i < n; i++) {
            if (!token.transferFrom(msg.sender, recipients[i], amounts[i])) {
                revert TransferFailed(recipients[i], amounts[i]);
            }
        }
    }
}
