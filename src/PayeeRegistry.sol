// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title PayeeRegistry — Confirmation of Payee for tUSD8 payments on Aevum
/// @notice Names are hashed off-chain (trim + lowercase, then keccak256 of the UTF-8 bytes)
///         so the registry never stores case-variant duplicates and never leaks the name
///         in plaintext beyond what the payee chooses to publish as `displayName`.
contract PayeeRegistry {
    struct Payee {
        address wallet;
        string displayName;
        bool active;
        uint64 updatedAt;
    }

    address public owner;
    uint256 public payeeCount;

    mapping(bytes32 => Payee) private _payees;      // nameHash => record
    mapping(address => bytes32) private _nameOf;     // wallet   => nameHash

    error NotOwner();
    error ZeroAddress();
    error EmptyName();
    error NameTaken(bytes32 nameHash);
    error WalletAlreadyNamed(address wallet);
    error NotPayee();
    error NameMismatch(bytes32 nameHash, address wallet);

    event PayeeRegistered(bytes32 indexed nameHash, address indexed wallet, string displayName);
    event PayeeRenamed(bytes32 indexed oldHash, bytes32 indexed newHash, address indexed wallet);
    event PayeeDeactivated(bytes32 indexed nameHash, address indexed wallet);

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    /// @notice Hash helper. Clients must normalise (trim, collapse spaces, lowercase) first.
    function hashName(string memory name) public pure returns (bytes32) {
        return keccak256(bytes(name));
    }

    /// @notice Register a payable name bound to the caller's wallet.
    function register(bytes32 nameHash, string calldata displayName) external {
        if (nameHash == bytes32(0)) revert EmptyName();
        if (bytes(displayName).length == 0) revert EmptyName();
        if (_payees[nameHash].wallet != address(0)) revert NameTaken(nameHash);
        if (_nameOf[msg.sender] != bytes32(0)) revert WalletAlreadyNamed(msg.sender);

        _payees[nameHash] = Payee({
            wallet: msg.sender,
            displayName: displayName,
            active: true,
            updatedAt: uint64(block.timestamp)
        });
        _nameOf[msg.sender] = nameHash;
        payeeCount += 1;

        emit PayeeRegistered(nameHash, msg.sender, displayName);
    }

    /// @notice Replace the caller's name. Old hash is freed so it can be claimed again.
    function rename(bytes32 newHash, string calldata displayName) external {
        bytes32 oldHash = _nameOf[msg.sender];
        if (oldHash == bytes32(0)) revert NotPayee();
        if (newHash == bytes32(0) || bytes(displayName).length == 0) revert EmptyName();
        if (_payees[newHash].wallet != address(0)) revert NameTaken(newHash);

        _payees[oldHash].active = false;
        _payees[newHash] = Payee({
            wallet: msg.sender,
            displayName: displayName,
            active: true,
            updatedAt: uint64(block.timestamp)
        });
        _nameOf[msg.sender] = newHash;

        emit PayeeRenamed(oldHash, newHash, msg.sender);
    }

    /// @notice Stop receiving payments under the current name.
    function deactivate() external {
        bytes32 h = _nameOf[msg.sender];
        if (h == bytes32(0)) revert NotPayee();
        _payees[h].active = false;
        _payees[h].updatedAt = uint64(block.timestamp);
        emit PayeeDeactivated(h, msg.sender);
    }

    /// @notice The single check a payment must pass: does this name resolve to this wallet?
    function confirm(bytes32 nameHash, address wallet) public view returns (bool) {
        Payee storage p = _payees[nameHash];
        return p.active && p.wallet == wallet;
    }

    function resolve(bytes32 nameHash) external view returns (Payee memory) {
        return _payees[nameHash];
    }

    function nameOf(address wallet) external view returns (bytes32) {
        return _nameOf[wallet];
    }

    /// @dev Owner may seize a name that is impersonating someone (proactive risk control).
    function ownerRevoke(bytes32 nameHash) external onlyOwner {
        Payee storage p = _payees[nameHash];
        if (p.wallet == address(0)) revert NameMismatch(nameHash, address(0));
        p.active = false;
        p.updatedAt = uint64(block.timestamp);
        emit PayeeDeactivated(nameHash, p.wallet);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        owner = newOwner;
    }
}
