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

## Live on Aevum Testnet

Both contracts are deployed and the flow has been executed against the real network
(chain `44005`, `tUSD8` at `0x456569838f1d43009A91ebA4263147Afd7233483`).

```
PayeeRegistry   0x5246b48c6791F1980f5F0d6b63b74A4940a2c7C8
SpendEnvelope   0xE9960C67813CAD672Afe48d93E5199712f85C529
owner           0x2d8ff0aAC4B5401960A1eCA691548f1544c322Aa
demo payee      0xE9783E5BD2A9aD91DC142d64E8872CAF7064D6eD   (self-registered "Warung Bu Sri")
session agent   0x3E29229E79528dfAe409F24FbeaC3e4FC4c4A377
```

Setup transactions:

| step | transaction |
|------|-------------|
| payee registers itself | [`0x0fdca39bdd9f0c32e15214a6aca1269b20fd9be9f244cbffb9203572affb9a57`](https://explorer-test.qday.info/tx/0x0fdca39bdd9f0c32e15214a6aca1269b20fd9be9f244cbffb9203572affb9a57) |
| envelope funded with 4 tUSD8 | [`0x3f5557e7da7a78fce38dbd1f68f95552c4710f0b77c562b471259f3a27bd48ca`](https://explorer-test.qday.info/tx/0x3f5557e7da7a78fce38dbd1f68f95552c4710f0b77c562b471259f3a27bd48ca) |
| session opened (2 tUSD8/tx, 4 tUSD8/day) | [`0xf1172291c56691c5f5f2f6df9dcf4380ac4c1c85d56a8af5e3ba2c388df8bcde`](https://explorer-test.qday.info/tx/0xf1172291c56691c5f5f2f6df9dcf4380ac4c1c85d56a8af5e3ba2c388df8bcde) |

Agent decisions on the live network:

| invoice | request | verdict | transaction |
|---------|---------|---------|-------------|
| AEV-001 | 1.5 tUSD8 → registered payee | **paid** | [`0xe547bc31fafe307bed978b417a45da3ae589e06456a11202f3c87d47c2e0e4eb`](https://explorer-test.qday.info/tx/0xe547bc31fafe307bed978b417a45da3ae589e06456a11202f3c87d47c2e0e4eb) |
| AEV-002 | 1.5 tUSD8 → same name, attacker wallet | **blocked** (1) | — |
| AEV-003 | 3.0 tUSD8 → registered payee, over per-tx cap | **blocked** (2) | — |
| AEV-004 | 1.5 tUSD8 → attacker wallet, refusal logged on-chain | **blocked** (1) | refusal: [`0x7257b7b40d2dd63f7343794aa2594c7f847f055b6197cd528540c3ee0ef2921c`](https://explorer-test.qday.info/tx/0x7257b7b40d2dd63f7343794aa2594c7f847f055b6197cd528540c3ee0ef2921c) |

Final state read back from the chain:

```
tUSD8  envelope    2.500000   (4.0 funded − 1.5 paid)
tUSD8  payee       1.500000   (exactly the invoice; no leakage)
tUSD8  attacker    0.150000   (pre-existing dust, unrelated — nothing arrived from this run)
session pymts/blocked   1 / 3   (every refusal counted on-chain, not just in logs)
```

The blocked counter is the part worth checking yourself: it lives in the session struct and
is incremented by `logBlocked()`, so a refusal leaves a permanent mark even though no money
moved. A refusal cannot be quietly dropped from the agent's own records.

## Evidence — local reproducible run

Reproduced end-to-end on a local anvil node with `scripts/anvil_e2e.sh`. Caps: 5 tUSD8 per
transaction, 10 tUSD8 per day. Envelope funded with 50 tUSD8.

| # | invoice | expected | actual | reason | transaction (anvil) |
|--:|---------|----------|--------|-------:|-------------|
| 1 | 2.5 → Warung Bu Sri (registered wallet) | pay | **paid** | 0 | `0xc71d58ccc25e29b62d6f2fa22ed7b4f19c6520485520468b6f020b6f22930dda` |
| 2 | 2.5 → **same name, attacker wallet** | refuse | **blocked** | 1 | — |
| 3 | 9.0 → registered payee (over per-tx cap) | refuse | **blocked** | 2 | — |
| 4 | 5.0 → registered payee | pay | **paid** | 0 | `0x354f806420fc35151c91cf9665359e8e00be2c3b762dafbe6807312e28b51bb4` |
| 5 | 4.0 → registered payee (10 already burned) | refuse | **blocked** | 3 | — |
| 6 | 1.0 → registered payee, after `revokeSession` | refuse | **blocked** | 4 | revoke: `0x55271912e8d735e46c85beb86aecb67245d315ee75693d8ebc06ab5f987b6ade` |

These hashes are on a local anvil chain, not on Aevum — reproducible in one command, and
that is the honest framing. The Aevum deployment below is wired and waiting on faucet gas.

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
AEVUM_RPC=https://rpc-test.qday.info
TUSD8_ADDRESS=0x456569838f1d43009A91ebA4263147Afd7233483
OWNER_PRIVATE_KEY=... bash scripts/deploy.sh
```

### Verified network facts

Checked directly against the chain, not copied from a blog post:

```
chain-id                44005            (0xABE5 — Aevum Testnet;
                                         44001 is QDay Origin mainnet, 44003 its testnet)
rpc                     https://rpc-test.qday.info
tUSD8                   0x456569838f1d43009A91ebA4263147Afd7233483
  name() / symbol()     "tUSD8" / "tUSD8"
  decimals()            6
  bytecode present      2,995 bytes at block 4,040,601
```

Gas is tQDAY, claimed from `https://faucet.qday.info` (5 tQDAY per 24h, plus a tUSD8 tab).
That faucet only accepts a connected wallet — there is no address-paste field — so the first
claim has to be signed by the deploying wallet. Once gas is in, the whole live demo is:

```bash
set -a && . ./.env && set +a
REGISTRY_ADDRESS=... ENVELOPE_ADDRESS=... bash scripts/aevum_seed.sh   # payees, funding, session
python3 agent/guardian.py agent/invoices.example.json
```

`scripts/aevum_seed.sh` registers each payee with that payee's own key, funds the envelope,
opens the session, and reads the resulting session struct back off the chain so the state
change is visible before the agent ever runs.

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
- The registry pins one wallet per name, first come first served. Entity disambiguation (two
  genuinely different "Warung Bu Sri") needs an identifier beyond the display name — the
  registry is keyed by `nameHash` + `wallet`, so adding a merchant ID is a small extension,
  but the UI for picking between them does not exist yet.
- Testnet-only: caps are enforced in base units and there is no oracle, so this is a payment
  primitive, not a fiat product.

## Layout

```
src/PayeeRegistry.sol      name ⇄ wallet registry, self-registered, normalised hashes
src/SpendEnvelope.sol      session keys, per-tx/daily caps, expiry, revocation, audit events
test/Envelope.t.sol        12 tests + MockTUSD8
agent/guardian.py          asyncio payer: confirm → preview → pay, JSONL + on-chain refusals
agent/invoices.example.json sample invoices including a lookalike payee
scripts/anvil_e2e.sh       one-command local proof (deploy, wire, ready to run)
scripts/deploy.sh          Aevum Testnet deployment
scripts/aevum_seed.sh      live demo seeding: payees self-register, fund, open session
```

MIT licensed.
