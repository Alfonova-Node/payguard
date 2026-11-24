// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address who) external view returns (uint256);
    function decimals() external view returns (uint8);
    function symbol() external view returns (string memory);
}

interface IPayeeRegistry {
    function confirm(bytes32 nameHash, address wallet) external view returns (bool);
}

/// @title SpendEnvelope — scoped session keys with hard spend caps for an autonomous payer
/// @notice The owner funds the envelope once, then hands an agent a session key that can
///         move tUSD8 only inside three limits: per-transaction cap, rolling daily cap, and
///         an expiry timestamp. Every payment must also pass Confirmation of Payee against
///         the registry, so a compromised agent cannot redirect funds to a lookalike name.
///         Revocation is a single transaction and takes effect on the next call.
contract SpendEnvelope {
    uint256 private constant DAY = 1 days;

    IERC20 public immutable token;
    IPayeeRegistry public immutable registry;
    address public owner;

    struct Session {
        bool active;
        bool allowAnyPayee;      // false => only payees allowlisted for this agent
        uint64 expiry;
        uint128 perTxCap;
        uint128 dailyCap;
        uint128 spentToday;
        uint64 day;              // block.timestamp / DAY of `spentToday`
        uint256 payments;
        uint256 blocked;         // blocked attempts recorded on-chain
    }

    mapping(address => Session) public sessions;
    mapping(address => mapping(bytes32 => bool)) public payeeAllowed;
    mapping(address => mapping(uint64 => uint128)) public dailySpent;

    error NotOwner();
    error NotAgent();
    error SessionInactive();
    error SessionExpired();
    error AmountZero();
    error CapExceeded(uint256 requested, uint256 cap);
    error DailyCapExceeded(uint256 requested, uint256 remaining);
    error PayeeNotConfirmed(bytes32 nameHash, address wallet);
    error PayeeNotAllowlisted(bytes32 nameHash);
    error TransferFailed();
    error ZeroAddress();

    event SessionCreated(address indexed agent, uint64 expiry, uint128 perTxCap, uint128 dailyCap, bool allowAnyPayee);
    event SessionRevoked(address indexed agent);
    event PayeeAllowlisted(address indexed agent, bytes32 indexed nameHash, bool allowed);
    event PaymentExecuted(
        address indexed agent,
        bytes32 indexed nameHash,
        address indexed to,
        uint256 amount,
        string memo,
        uint256 spentToday,
        uint256 day
    );
    event PaymentBlocked(address indexed agent, bytes32 indexed nameHash, address indexed to, uint256 amount, uint8 reason);
    event Funded(address indexed from, uint256 amount);
    event Withdrawn(address indexed to, uint256 amount);

    /// @dev reason codes for PaymentBlocked, mirrored in the agent client
    uint8 public constant REASON_PAYEE_MISMATCH = 1;
    uint8 public constant REASON_PER_TX_CAP = 2;
    uint8 public constant REASON_DAILY_CAP = 3;
    uint8 public constant REASON_EXPIRED = 4;
    uint8 public constant REASON_NOT_ALLOWLISTED = 5;

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(address token_, address registry_) {
        if (token_ == address(0) || registry_ == address(0)) revert ZeroAddress();
        token = IERC20(token_);
        registry = IPayeeRegistry(registry_);
        owner = msg.sender;
    }

    // ───────────────────────────────────────────── owner surface

    function fund(uint256 amount) external onlyOwner {
        if (amount == 0) revert AmountZero();
        if (!token.transferFrom(msg.sender, address(this), amount)) revert TransferFailed();
        emit Funded(msg.sender, amount);
    }

    function createSession(
        address agent,
        uint64 expiry,
        uint128 perTxCap,
        uint128 dailyCap,
        bool allowAnyPayee
    ) external onlyOwner {
        if (agent == address(0)) revert ZeroAddress();
        if (expiry <= block.timestamp) revert SessionExpired();
        sessions[agent] = Session({
            active: true,
            allowAnyPayee: allowAnyPayee,
            expiry: expiry,
            perTxCap: perTxCap,
            dailyCap: dailyCap,
            spentToday: 0,
            day: uint64(block.timestamp / DAY),
            payments: 0,
            blocked: 0
        });
        emit SessionCreated(agent, expiry, perTxCap, dailyCap, allowAnyPayee);
    }

    function revokeSession(address agent) external onlyOwner {
        sessions[agent].active = false;
        emit SessionRevoked(agent);
    }

    function setPayeeAllowed(address agent, bytes32 nameHash, bool allowed) external onlyOwner {
        payeeAllowed[agent][nameHash] = allowed;
        emit PayeeAllowlisted(agent, nameHash, allowed);
    }

    function withdraw(address to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        if (!token.transfer(to, amount)) revert TransferFailed();
        emit Withdrawn(to, amount);
    }

    // ───────────────────────────────────────────── agent surface

    /// @notice Dry-run the exact checks `pay` would perform. Free, and the agent calls it first.
    function previewPay(bytes32 nameHash, address to, uint256 amount)
        public
        view
        returns (bool ok, uint8 reason, uint256 remainingToday)
    {
        Session storage s = sessions[msg.sender];
        (uint128 used,) = _currentUsage(msg.sender);
        remainingToday = s.dailyCap > used ? uint256(s.dailyCap - used) : 0;

        if (!s.active) return (false, REASON_EXPIRED, remainingToday);
        if (block.timestamp > s.expiry) return (false, REASON_EXPIRED, remainingToday);
        if (!s.allowAnyPayee && !payeeAllowed[msg.sender][nameHash]) {
            return (false, REASON_NOT_ALLOWLISTED, remainingToday);
        }
        if (!registry.confirm(nameHash, to)) return (false, REASON_PAYEE_MISMATCH, remainingToday);
        if (amount > s.perTxCap) return (false, REASON_PER_TX_CAP, remainingToday);
        if (amount > remainingToday) return (false, REASON_DAILY_CAP, remainingToday);
        return (true, 0, remainingToday);
    }

    /// @notice Execute a payment inside the envelope.
    function pay(bytes32 nameHash, address to, uint256 amount, string calldata memo) external returns (bool) {
        if (amount == 0) revert AmountZero();
        Session storage s = sessions[msg.sender];
        if (!s.active) revert SessionInactive();
        if (block.timestamp > s.expiry) revert SessionExpired();
        if (!s.allowAnyPayee && !payeeAllowed[msg.sender][nameHash]) revert PayeeNotAllowlisted(nameHash);
        if (!registry.confirm(nameHash, to)) revert PayeeNotConfirmed(nameHash, to);
        if (amount > s.perTxCap) revert CapExceeded(amount, s.perTxCap);

        (uint128 used, uint64 day) = _currentUsage(msg.sender);
        uint256 remaining = s.dailyCap > used ? uint256(s.dailyCap - used) : 0;
        if (amount > remaining) revert DailyCapExceeded(amount, remaining);

        dailySpent[msg.sender][day] = used + uint128(amount);
        s.spentToday = used + uint128(amount);
        s.day = day;
        s.payments += 1;

        if (!token.transfer(to, amount)) revert TransferFailed();

        emit PaymentExecuted(msg.sender, nameHash, to, amount, memo, s.spentToday, day);
        return true;
    }

    /// @notice Record a refusal on-chain so the audit trail shows what the agent tried to do
    ///         and why it stopped. Only callable by a live session holder, costs only gas.
    function logBlocked(bytes32 nameHash, address to, uint256 amount, uint8 reason) external {
        Session storage s = sessions[msg.sender];
        if (!s.active) revert SessionInactive();
        s.blocked += 1;
        emit PaymentBlocked(msg.sender, nameHash, to, amount, reason);
    }

    // ───────────────────────────────────────────── views

    function _currentUsage(address agent) internal view returns (uint128 used, uint64 day) {
        day = uint64(block.timestamp / DAY);
        used = dailySpent[agent][day];
    }

    function sessionOf(address agent) external view returns (Session memory) {
        return sessions[agent];
    }

    function remainingToday(address agent) external view returns (uint256) {
        Session storage s = sessions[agent];
        (uint128 used,) = _currentUsage(agent);
        return s.dailyCap > used ? uint256(s.dailyCap - used) : 0;
    }

    function balance() external view returns (uint256) {
        return token.balanceOf(address(this));
    }
}
