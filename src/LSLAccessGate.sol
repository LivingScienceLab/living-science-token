// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @dev Minimal burn surface of the LSL token (ERC20Burnable). Kept separate from IERC20 so
///      the gate can destroy collected tokens when the spent-LSL sink is set to `Burn`.
interface IERC20Burnable {
    function burn(uint256 amount) external;
}

/// @title LSL Access Gate (spend-to-access)
/// @notice Users spend Living Science Token (LSL) to obtain access to off-chain infrastructure /
///         IP assets. This contract is the **on-chain record of payment and entitlement**; an
///         off-chain gatekeeper reads this state (subscription expiry / remaining credits) to
///         decide whether to serve a request. It does not, and cannot, gate the off-chain
///         service by itself.
/// @dev    Deliberately decoupled from the token: LSL is immutable and ownerless, so all the
///         mutable, business-logic knobs (prices, the spent-LSL sink, the operator allowlist,
///         the pause switch) live here behind `Ownable`. Two access models are supported per
///         resource:
///           - PerUse:        a purchase adds N redeemable credits; an operator `consume`s them.
///           - Subscription:  a purchase extends a time-based expiry by N periods.
///         Each spent payment is routed to the configured sink: forwarded to a `treasury`
///         address, or burned (reducing LSL total supply — the token is ERC20Burnable).
contract LSLAccessGate is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice How access for a resource is metered.
    enum AccessModel {
        PerUse, // purchase buys redeemable credits (price = LSL per use)
        Subscription // purchase buys time (price = LSL per period, `duration` = period length)
    }

    /// @notice Where spent LSL goes after a purchase.
    enum SpentSink {
        Treasury, // forwarded to `treasury`
        Burn // destroyed via ERC20Burnable.burn (LSL supply shrinks)
    }

    /// @param price    LSL (in wei, 18 decimals) charged per unit purchased — per use for
    ///                 PerUse, or per subscription period for Subscription.
    /// @param duration Seconds granted per period (Subscription only; ignored for PerUse).
    /// @param model    Which access model this resource uses.
    /// @param active   Whether the resource can currently be purchased.
    struct Resource {
        uint128 price;
        uint64 duration;
        AccessModel model;
        bool active;
    }

    /// @notice The LSL token this gate collects.
    IERC20 public immutable token;

    /// @notice Current spent-LSL sink (Treasury or Burn).
    SpentSink public sink;

    /// @notice Destination for spent LSL when `sink == Treasury`. May be zero only while the
    ///         sink is Burn.
    address public treasury;

    /// @notice resourceId => its configuration.
    mapping(bytes32 => Resource) public resources;

    /// @notice user => resourceId => remaining redeemable uses (PerUse resources).
    mapping(address => mapping(bytes32 => uint256)) public credits;

    /// @notice user => resourceId => unix timestamp the subscription is valid until
    ///         (Subscription resources). Access is live while `block.timestamp < expiry`.
    mapping(address => mapping(bytes32 => uint64)) public accessExpiry;

    /// @notice Addresses permitted to redeem PerUse credits via `consume` (the off-chain
    ///         backend that serves the gated infrastructure).
    mapping(address => bool) public operators;

    event ResourceSet(bytes32 indexed id, AccessModel model, uint256 price, uint64 duration, bool active);
    event SinkSet(SpentSink sink, address indexed treasury);
    event OperatorSet(address indexed operator, bool allowed);
    event Purchased(
        address indexed user, bytes32 indexed id, AccessModel model, uint256 quantity, uint256 cost, uint64 expiry
    );
    event Consumed(address indexed user, bytes32 indexed id, uint256 amount, uint256 remaining);
    event Collected(address indexed to, uint256 amount);
    event Burned(uint256 amount);

    error UnknownOrInactiveResource(bytes32 id);
    error WrongAccessModel(bytes32 id);
    error ZeroQuantity();
    error ZeroAddress();
    error TreasuryRequired();
    error NotOperator(address caller);
    error InsufficientCredits(address user, bytes32 id, uint256 have, uint256 want);

    modifier onlyOperator() {
        if (!operators[msg.sender]) revert NotOperator(msg.sender);
        _;
    }

    /// @param token_    The LSL token address.
    /// @param sink_     Initial spent-LSL sink.
    /// @param treasury_ Treasury address (required if `sink_ == Treasury`; may be zero for Burn).
    /// @param owner_    Admin (price/sink/operator/pause control) — intended to be the Ledger.
    constructor(address token_, SpentSink sink_, address treasury_, address owner_) Ownable(owner_) {
        if (token_ == address(0)) revert ZeroAddress();
        if (sink_ == SpentSink.Treasury && treasury_ == address(0)) revert TreasuryRequired();
        token = IERC20(token_);
        sink = sink_;
        treasury = treasury_;
        emit SinkSet(sink_, treasury_);
    }

    /* ----------------------------- admin ----------------------------- */

    /// @notice Create or update a resource's pricing and access model.
    function setResource(bytes32 id, AccessModel model, uint128 price, uint64 duration, bool active)
        external
        onlyOwner
    {
        resources[id] = Resource({price: price, duration: duration, model: model, active: active});
        emit ResourceSet(id, model, price, duration, active);
    }

    /// @notice Toggle whether an existing resource can be purchased.
    function setResourceActive(bytes32 id, bool active) external onlyOwner {
        resources[id].active = active;
        Resource storage r = resources[id];
        emit ResourceSet(id, r.model, r.price, r.duration, active);
    }

    /// @notice Change where spent LSL goes. Treasury must be non-zero when selecting Treasury.
    function setSink(SpentSink sink_, address treasury_) external onlyOwner {
        if (sink_ == SpentSink.Treasury && treasury_ == address(0)) revert TreasuryRequired();
        sink = sink_;
        treasury = treasury_;
        emit SinkSet(sink_, treasury_);
    }

    /// @notice Allow/deny an address to redeem PerUse credits via `consume`.
    function setOperator(address operator, bool allowed) external onlyOwner {
        if (operator == address(0)) revert ZeroAddress();
        operators[operator] = allowed;
        emit OperatorSet(operator, allowed);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /* --------------------------- purchase ---------------------------- */

    /// @notice Pay LSL to obtain access to `id`. For PerUse, `quantity` is the number of uses;
    ///         for Subscription, `quantity` is the number of periods. Caller must have approved
    ///         this contract for at least `quote(id, quantity)` LSL (or use `purchaseWithPermit`).
    /// @return cost The total LSL (wei) charged.
    function purchase(bytes32 id, uint256 quantity) external whenNotPaused nonReentrant returns (uint256 cost) {
        return _purchase(id, quantity);
    }

    /// @notice Same as `purchase`, but consumes an EIP-2612 permit so no prior `approve` tx is
    ///         needed. `value` is the allowance the signature authorizes (use `quote(...)`).
    function purchaseWithPermit(
        bytes32 id,
        uint256 quantity,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external whenNotPaused nonReentrant returns (uint256 cost) {
        // Permit failures (e.g. a front-run that already set the allowance) must not brick the
        // purchase: swallow the permit revert and rely on the allowance check in transferFrom.
        try IERC20Permit(address(token)).permit(msg.sender, address(this), value, deadline, v, r, s) {} catch {}
        return _purchase(id, quantity);
    }

    function _purchase(bytes32 id, uint256 quantity) internal returns (uint256 cost) {
        if (quantity == 0) revert ZeroQuantity();
        Resource memory r = resources[id];
        if (!r.active) revert UnknownOrInactiveResource(id);

        cost = uint256(r.price) * quantity;
        _collect(msg.sender, cost);

        uint64 expiry;
        if (r.model == AccessModel.PerUse) {
            credits[msg.sender][id] += quantity;
        } else {
            uint64 current = accessExpiry[msg.sender][id];
            uint64 base = current > block.timestamp ? current : uint64(block.timestamp);
            expiry = base + uint64(uint256(r.duration) * quantity);
            accessExpiry[msg.sender][id] = expiry;
        }

        emit Purchased(msg.sender, id, r.model, quantity, cost, expiry);
    }

    /// @dev Pull `amount` LSL from `from` into this contract, then route it to the sink.
    function _collect(address from, uint256 amount) internal {
        token.safeTransferFrom(from, address(this), amount);
        if (sink == SpentSink.Burn) {
            IERC20Burnable(address(token)).burn(amount);
            emit Burned(amount);
        } else {
            token.safeTransfer(treasury, amount);
            emit Collected(treasury, amount);
        }
    }

    /* ---------------------------- redeem ----------------------------- */

    /// @notice Redeem `amount` PerUse credits for `user` against `id`. Called by an authorized
    ///         operator (the backend) as it serves requests.
    function consume(address user, bytes32 id, uint256 amount) external onlyOperator {
        if (amount == 0) revert ZeroQuantity();
        if (resources[id].model != AccessModel.PerUse) revert WrongAccessModel(id);
        uint256 have = credits[user][id];
        if (have < amount) revert InsufficientCredits(user, id, have, amount);
        uint256 remaining = have - amount;
        credits[user][id] = remaining;
        emit Consumed(user, id, amount, remaining);
    }

    /* ----------------------------- views ----------------------------- */

    /// @notice Total LSL (wei) to buy `quantity` units of `id`.
    function quote(bytes32 id, uint256 quantity) external view returns (uint256) {
        return uint256(resources[id].price) * quantity;
    }

    /// @notice Whether `user` currently has access to `id`: a live subscription, or >0 credits.
    function hasAccess(address user, bytes32 id) external view returns (bool) {
        Resource memory r = resources[id];
        if (r.model == AccessModel.Subscription) {
            return accessExpiry[user][id] > block.timestamp;
        }
        return credits[user][id] > 0;
    }
}
