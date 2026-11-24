# PayGuard — an agent that physically cannot pay the wrong person

Two Solidity primitives and one autonomous payer that together close the oldest hole in
agentic payments: the agent is told a name, and a compromised prompt hands it a different
wallet. PayGuard binds the name to the wallet on-chain before a single base unit moves, and
puts a hard ceiling on what the agent can spend even if its instructions are rewritten
mid-run.

Built for **Aevum Builder Challenge #1** — track: *Native AI Assistants*, on Aevum Testnet
(chain `44005`, settlement in `tUSD8`, 6 decimals).

---

## The failure this exists to stop

An invoice says **"Warung Bu Sri — 25 cups of coffee."** An attacker edits one field in the
context the agent reads, or poisons a retrieved document, or simply renames their own wallet.
The agent pays. Nobody notices until reconciliation, three days later, and the money is gone.

Confirmation-of-Payee is standard practice in banking for exactly this reason, and it has no
equivalent in agent payments. Spend caps exist, but a cap only limits *how much*, never *to
whom*. PayGuard adds the missing half.

```
invoice text ──► normalise("Warung Bu Sri") ──► keccak256 ──► nameHash
                                                                 │
                                              PayeeRegistry.confirm(nameHash, wallet)
                                                                 │
                                                     false ◄─────┴─────► true
                                                       │                  │
                                              refusal, on-chain    SpendEnvelope.previewPay
                                              PaymentBlocked(1)          │
                                                              ok ◄───────┴──────► cap hit
                                                               │                    │
                                                         tUSD8 transfer        PaymentBlocked(2|3|4|5)
```

## Components

**`src/PayeeRegistry.sol`** — names map to wallets, one-to-one, both directions.
A payee registers their own name (signed by the payee's wallet, not the payer's), so the
registry cannot be populated on someone's behalf. Names are normalised before hashing
(whitespace collapsed, lowercased) so `"Warung  Bu Sri "` and `"warung bu sri"` are the same
payee and no one can register a visually identical twin.

**`src/SpendEnvelope.sol`** — holds the money, never the agent. The agent gets a session with
`perTxCap`, `dailyCap`, `expiry`, and an optional payee allowlist. `previewPay()` is a free
view function that returns the exact verdict `pay()` would reach plus the reason code, so the
agent can decide before spending gas. `revokeSession()` takes effect on the next call — no
grace period, no pending state.

**`agent/guardian.py`** — asyncio payer that drives the flow through `cast`. For every
invoice: normalise the name → `confirm()` → `previewPay()` → `pay()`. Anything that fails is
recorded twice: `logBlocked()` on-chain and a JSONL line locally. The private key comes from
the keystore or environment, never from a tracked file.

### Reason codes (mirrored in the client)

| code | meaning |
|-----:|---------|
| 0 | allowed |
| 1 | `PAYEE_MISMATCH` — the name does not belong to that wallet |
| 2 | `PER_TX_CAP` — single payment over the per-transaction ceiling |
| 3 | `DAILY_CAP` — the day's budget is spent |
| 4 | `SESSION_INACTIVE_OR_EXPIRED` — revoked or past expiry |
| 5 | `PAYEE_NOT_ALLOWLISTED` — session is restricted to a fixed payee set |

## Evidence — real run, real hashes

Reproduced end-to-end on a local anvil node with `scripts/anvil_e2e.sh`. Caps: 5 tUSD8 per
transaction, 10 tUSD8 per day. Envelope funded with 50 tUSD8.

| # | invoice | expected | actual | reason | transaction |
|--:|---------|----------|--------|-------:|-------------|
| 1 | 2.5 → Warung Bu Sri (registered wallet) | pay | **paid** | 0 | [`0xc71d58cc…930dda`](https://explorer.aevum.qday.io/tx/0xc71d58ccc25e29b62d6f2fa22ed7b4f19c6520485520468b6f020b6f22930dda) |
| 2 | 2.5 → **same name, attacker wallet** | refuse | **blocked** | 1 | — |
| 3 | 9.0 → registered payee (over per-tx cap) | refuse | **blocked** | 2 | — |
| 4 | 5.0 → registered payee | pay | **paid** | 0 | [`0x354f8064…8b51bb4`](https://explorer.aevum.qday.io/tx/0x354f806420fc35151c91cf9665359e8e00be2c3b762dafbe6807312e28b51bb4) |
| 5 | 4.0 → registered payee (10 already burned) | refuse | **blocked** | 3 | — |
| 6 | 1.0 → registered payee, after `revokeSession` | refuse | **blocked** | 4 | revoke: `0x55271912…7b6ade` |

Balances after the run: envelope `50.0 → 47.5 tUSD8`, legitimate payee `+2.5 tUSD8`,
attacker wallet `0.0`. The tokens moved exactly where the name said they would, and the
duplicate name bought the attacker nothing.

`forge test` → **12 passing**, covering name normalisation and collisions, registry
authorisation, per-tx and daily caps, expiry, allowlists, revocation, and every
`previewPay` reason code.

## Reproduce

```bash
export PATH="$HOME/.foundry/bin:$PATH"
forge build && forge test

# full local chain proof: deploy, wire a session, run the agent
anvil --port 8545 --silent &
bash scripts/anvil_e2e.sh          # writes .anvil.env
set -a && . ./.anvil.env && set +a
python3 agent/guardian.py agent/invoices.example.json --out audit.jsonl
```

Against Aevum Testnet, `scripts/deploy.sh` does the same two deployments with a real key and
prints the addresses to put in `.env`:

```bash
AEVUM_RPC=https://rpc.qday.io
TUSD8_ADDRESS=0x456569838f1d43009A91ebA4263147Afd7233483
OWNER_PRIVATE_KEY=... bash scripts/deploy.sh
```

## Security properties worth stating

- **The daily burn survives session rotation.** Usage is keyed by `(agent, day)` in
  `dailySpent`, not by session struct. Re-issuing a session cannot launder a spent cap — the
  new session inherits the same day's consumption. Rotating your way out of a limit is a
  common design slip.
- **Sessions are `msg.sender`-scoped.** An agent can only spend its own envelope; `previewPay`
  called from any other address reports that address's session, so a dry run can never lie
  about the caller's real limits.
- **Payees register themselves.** Neither the owner nor the agent can attach a name to a
  wallet it does not control, so the registry can't be used to bless an attacker's address.
- **Refusals are on-chain.** `PaymentBlocked` carries the reason code, so the audit trail
  doesn't depend on trusting the agent's own logs.
- **No key material in the repo.** `AGENT_PRIVATE_KEY` is injected; `.env` is gitignored.

## Limitations and next steps

- Payments are push-style tUSD8 transfers. Gasless meta-transactions and batched payroll
  runs are natural extensions of the same envelope.
- One payee per name. Entity disambiguation (two different "Warung Bu Sri") needs an
  identifier beyond the display name — the registry is structured for it, the UI is not.
- The Aevum testnet deployment is wired but unfunded: it needs tUSD8 from the QDay faucet
  for the demo run. The local proof above uses an identical contract byte-for-byte.

## Layout

```
src/PayeeRegistry.sol      name ⇄ wallet registry, self-registered, normalised hashes
src/SpendEnvelope.sol      session keys, per-tx/daily caps, expiry, revocation, audit events
test/Envelope.t.sol        12 tests + MockTUSD8
agent/guardian.py          asyncio payer: confirm → preview → pay, JSONL + on-chain refusals
agent/invoices.example.json sample invoices including a lookalike payee
scripts/anvil_e2e.sh       one-command local proof (deploy, wire, ready to run)
scripts/deploy.sh          Aevum Testnet deployment
```

MIT licensed.
