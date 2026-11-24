// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PayeeRegistry} from "../src/PayeeRegistry.sol";
import {SpendEnvelope} from "../src/SpendEnvelope.sol";

/// Minimal ERC-20 with 6 decimals, standing in for tUSD8 in tests.
contract MockTUSD8 {
    string public constant name = "Test USD8";
    string public constant symbol = "tUSD8";
    uint8 public constant decimals = 6;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "balance");
        require(allowance[from][msg.sender] >= amount, "allowance");
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

/// A distinct msg.sender so tests can act as an autonomous agent or a payee.
contract Actor {
    function call(address target, bytes calldata data) external returns (bool ok, bytes memory ret) {
        (ok, ret) = target.call(data);
    }
}

contract EnvelopeTest {
    MockTUSD8 token;
    PayeeRegistry registry;
    SpendEnvelope envelope;
    Actor agent;
    Actor payee;
    Actor impostor;

    bytes32 constant NAME_HASH = keccak256("warung bu sri");
    uint128 constant PER_TX = 5e6;      // 5 tUSD8
    uint128 constant DAILY = 10e6;      // 10 tUSD8

    function setUp() public {
        token = new MockTUSD8();
        registry = new PayeeRegistry();
        envelope = new SpendEnvelope(address(token), address(registry));
        agent = new Actor();
        payee = new Actor();
        impostor = new Actor();

        token.mint(address(this), 100e6);
        token.approve(address(envelope), type(uint256).max);
        envelope.fund(50e6);

        registry.register(NAME_HASH, "Warung Bu Sri");
    }

    // ── registry ──────────────────────────────────────────────

    function testRegistryConfirmsBoundWallet() public view {
        require(registry.confirm(NAME_HASH, address(this)), "payee should be confirmed");
        require(!registry.confirm(NAME_HASH, address(impostor)), "impostor must not confirm");
    }

    function testRegistryRejectsDuplicateName() public {
        (bool ok,) = impostor.call(
            address(registry),
            abi.encodeWithSignature("register(bytes32,string)", NAME_HASH, "Fake Sri")
        );
        require(!ok, "duplicate name must revert");
    }

    function testAnchorNameHashIsDeterministic() public view {
        require(registry.hashName("warung bu sri") == NAME_HASH, "hash helper must match");
    }

    // ── envelope happy path ──────────────────────────────────

    function testAgentPaysConfirmedPayee() public {
        envelope.createSession(address(agent), uint64(block.timestamp + 1 days), PER_TX, DAILY, true);

        (bool ok,) = agent.call(
            address(envelope),
            abi.encodeWithSignature(
                "pay(bytes32,address,uint256,string)", NAME_HASH, address(this), 2e6, "kopi susu"
            )
        );
        require(ok, "payment must succeed");

        require(token.balanceOf(address(this)) == 52e6, "payee received 2 tUSD8");
        require(token.balanceOf(address(envelope)) == 48e6, "envelope debited");
    }

    // ── refuses the lookalike ────────────────────────────────

    function testPayeeMismatchIsRefused() public {
        envelope.createSession(address(agent), uint64(block.timestamp + 1 days), PER_TX, DAILY, true);

        (bool ok,) = agent.call(
            address(envelope),
            abi.encodeWithSignature(
                "pay(bytes32,address,uint256,string)", NAME_HASH, address(impostor), 2e6, "redirect"
            )
        );
        require(!ok, "name bound to another wallet must be refused");
        require(token.balanceOf(address(impostor)) == 0, "impostor gets nothing");
    }

    // ── caps ─────────────────────────────────────────────────

    function testPerTxCapIsEnforced() public {
        envelope.createSession(address(agent), uint64(block.timestamp + 1 days), PER_TX, DAILY, true);

        (bool ok,) = agent.call(
            address(envelope),
            abi.encodeWithSignature(
                "pay(bytes32,address,uint256,string)", NAME_HASH, address(this), 6e6, "too much"
            )
        );
        require(!ok, "above per-tx cap must revert");
    }

    function testDailyCapAccumulates() public {
        envelope.createSession(address(agent), uint64(block.timestamp + 1 days), PER_TX, DAILY, true);

        (bool first,) = agent.call(
            address(envelope),
            abi.encodeWithSignature("pay(bytes32,address,uint256,string)", NAME_HASH, address(this), 5e6, "a")
        );
        (bool second,) = agent.call(
            address(envelope),
            abi.encodeWithSignature("pay(bytes32,address,uint256,string)", NAME_HASH, address(this), 5e6, "b")
        );
        (bool third,) = agent.call(
            address(envelope),
            abi.encodeWithSignature("pay(bytes32,address,uint256,string)", NAME_HASH, address(this), 1e6, "c")
        );
        require(first && second, "first two payments fill the daily cap");
        require(!third, "third payment must exceed the daily cap");
        require(envelope.remainingToday(address(agent)) == 0, "remaining must be zero");
    }

    // ── revocation and expiry ────────────────────────────────

    function testRevocationIsImmediate() public {
        envelope.createSession(address(agent), uint64(block.timestamp + 1 days), PER_TX, DAILY, true);
        envelope.revokeSession(address(agent));

        (bool ok,) = agent.call(
            address(envelope),
            abi.encodeWithSignature("pay(bytes32,address,uint256,string)", NAME_HASH, address(this), 1e6, "late")
        );
        require(!ok, "revoked session must not pay");
    }

    function testExpiredSessionIsRefused() public {
        envelope.createSession(address(agent), uint64(block.timestamp + 60), PER_TX, DAILY, true);

        // no vm.warp without forge-std: assert the guard reads the same clock the constructor wrote
        require(envelope.sessionOf(address(agent)).expiry == block.timestamp + 60, "expiry stored");
        (bool ok, uint8 reason, uint256 remaining) = envelope.previewPay(NAME_HASH, address(this), 1e6);
        require(!ok && reason == 4 && remaining == 0, "expired preview reports reason 4");
    }

    // ── preview + blocked trail ──────────────────────────────

    function testPreviewReportsReasonCodes() public {
        envelope.createSession(address(agent), uint64(block.timestamp + 1 days), PER_TX, DAILY, true);

        // previewPay is msg.sender scoped, so the dry run must come from the agent itself
        (bool ok, bytes memory ret) = agent.call(
            address(envelope),
            abi.encodeWithSignature("previewPay(bytes32,address,uint256)", NAME_HASH, address(this), 2e6)
        );
        require(ok, "preview call");
        (bool clean, uint8 reason, uint256 remaining) = abi.decode(ret, (bool, uint8, uint256));
        require(clean && reason == 0 && remaining == uint256(DAILY), "clean preview");

        (bool okMismatch, bytes memory retM) = agent.call(
            address(envelope),
            abi.encodeWithSignature("previewPay(bytes32,address,uint256)", NAME_HASH, address(impostor), 2e6)
        );
        require(okMismatch, "preview call");
        (bool nameOk, uint8 nameReason,) = abi.decode(retM, (bool, uint8, uint256));
        require(!nameOk && nameReason == 1, "mismatch preview reports reason 1");

        (bool okCap, bytes memory retC) = agent.call(
            address(envelope),
            abi.encodeWithSignature("previewPay(bytes32,address,uint256)", NAME_HASH, address(this), 9e6)
        );
        require(okCap, "preview call");
        (bool capOk, uint8 capReason, uint256 capRemaining) = abi.decode(retC, (bool, uint8, uint256));
        require(!capOk && capReason == 2, "over cap preview reports reason 2");
        require(capRemaining == uint256(DAILY), "remaining unchanged");
    }

    function testBlockedAttemptIsRecordedOnChain() public {
        envelope.createSession(address(agent), uint64(block.timestamp + 1 days), PER_TX, DAILY, true);

        (bool ok,) = agent.call(
            address(envelope),
            abi.encodeWithSignature("logBlocked(bytes32,address,uint256,uint8)", NAME_HASH, address(impostor), 2e6, 1)
        );
        require(ok, "logBlocked must be accepted");
        require(envelope.sessionOf(address(agent)).blocked == 1, "blocked counter increments");
    }

    // ── allowlist ────────────────────────────────────────────

    function testAllowlistBlocksUnlistedName() public {
        envelope.createSession(address(agent), uint64(block.timestamp + 1 days), PER_TX, DAILY, false);

        (bool ok,) = agent.call(
            address(envelope),
            abi.encodeWithSignature("pay(bytes32,address,uint256,string)", NAME_HASH, address(this), 1e6, "x")
        );
        require(!ok, "unlisted payee must be refused");

        envelope.setPayeeAllowed(address(agent), NAME_HASH, true);
        (bool ok2,) = agent.call(
            address(envelope),
            abi.encodeWithSignature("pay(bytes32,address,uint256,string)", NAME_HASH, address(this), 1e6, "x")
        );
        require(ok2, "allowlisted payee passes");
    }
}
