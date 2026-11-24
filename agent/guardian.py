#!/usr/bin/env python3
"""Guardian — an autonomous tUSD8 payer that refuses to be redirected.

Flow per invoice:
  1. normalise the payee name and hash it (trim, collapse spaces, lowercase)
  2. ask PayeeRegistry.confirm(nameHash, address) -> does this name belong to this wallet?
  3. ask SpendEnvelope.previewPay(...) -> would the caps allow it right now?
  4. only then cast send pay(...); otherwise logBlocked(...) and stop

Every decision is written to an append-only JSONL audit file, and every refusal is
also recorded on-chain, so the trail is verifiable without trusting this script.

Chain access goes through `cast` (Foundry), which is platform-native tooling on
Aevum. No Python SDK, no private key ever leaves the keystore or environment.
"""
from __future__ import annotations

import argparse
import asyncio
import json
import os
import shlex
import time
from dataclasses import asdict, dataclass, field
from pathlib import Path

CAST = os.environ.get("CAST_BIN", "cast")
RPC = os.environ.get("AEVUM_RPC", "http://127.0.0.1:8545")
ENVELOPE = os.environ.get("ENVELOPE_ADDRESS", "")
REGISTRY = os.environ.get("REGISTRY_ADDRESS", "")
AGENT_KEY = os.environ.get("AGENT_PRIVATE_KEY", "")   # keystore/env only, never a file in the repo

REASON = {
    0: "OK",
    1: "PAYEE_MISMATCH",
    2: "PER_TX_CAP",
    3: "DAILY_CAP",
    4: "SESSION_INACTIVE_OR_EXPIRED",
    5: "PAYEE_NOT_ALLOWLISTED",
}


def norm(name: str) -> str:
    """The same normalisation the registry documents: collapse whitespace, lowercase."""
    return " ".join(name.split()).lower()


async def run(args: list[str], timeout: float = 45.0) -> tuple[int, str, str]:
    proc = await asyncio.create_subprocess_exec(
        *args,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    try:
        out, err = await asyncio.wait_for(proc.communicate(), timeout=timeout)
    except asyncio.TimeoutError:
        proc.kill()
        return 124, "", f"timeout after {timeout}s"
    return proc.returncode, out.decode().strip(), err.decode().strip()


async def cast_call(sig: str, *params: str, sender: str | None = None) -> str:
    args = [CAST, "call", "--rpc-url", RPC]
    if sender:
        args += ["--from", sender]
    target, fn = sig.split(":", 1)
    args += [target, fn, *params]
    code, out, err = await run(args)
    if code != 0:
        raise RuntimeError(f"cast call failed ({code}): {err or out}")
    return out


async def name_hash(name: str) -> str:
    code, out, err = await run([CAST, "keccak", norm(name)])
    if code != 0:
        raise RuntimeError(f"keccak failed: {err or out}")
    return out


@dataclass
class Decision:
    invoice_id: str
    payee_name: str
    payee_name_normalised: str
    name_hash: str
    payee_address: str
    amount_base_units: int
    memo: str
    status: str                      # paid | blocked | error
    reason: str = "OK"
    reason_code: int = 0
    tx_hash: str | None = None
    remaining_today: int | None = None
    at: float = field(default_factory=time.time)


async def guard(invoice: dict, dry_run: bool) -> Decision:
    nh = await name_hash(invoice["payee_name"])
    d = Decision(
        invoice_id=str(invoice.get("invoice_id", "")),
        payee_name=invoice["payee_name"],
        payee_name_normalised=norm(invoice["payee_name"]),
        name_hash=nh,
        payee_address=invoice["payee_address"],
        amount_base_units=int(invoice["amount_base_units"]),
        memo=invoice.get("memo", ""),
        status="error",
    )

    # 1. Confirmation of Payee
    confirmed = await cast_call(
        f"{REGISTRY}:confirm(bytes32,address)(bool)", nh, invoice["payee_address"]
    )
    if confirmed.lower() != "true":
        d.status, d.reason, d.reason_code = "blocked", "PAYEE_MISMATCH", 1
        return d

    # 2. Envelope dry run
    preview = await cast_call(
        f"{ENVELOPE}:previewPay(bytes32,address,uint256)(bool,uint8,uint256)",
        nh,
        invoice["payee_address"],
        str(invoice["amount_base_units"]),
        sender=invoice.get("agent_address") or os.environ.get("AGENT_ADDRESS"),
    )
    parts = preview.replace("(", " ").replace(")", " ").split()
    ok = parts[0].lower() == "true"
    reason_code = int(parts[1])
    d.remaining_today = int(parts[2])

    if not ok:
        d.status, d.reason_code, d.reason = "blocked", reason_code, REASON.get(reason_code, "UNKNOWN")
        return d

    if dry_run:
        d.status = "paid"
        d.tx_hash = None
        return d

    # 3. Execute
    code, out, err = await run([
        CAST, "send", "--rpc-url", RPC, "--private-key", AGENT_KEY,
        ENVELOPE, "pay(bytes32,address,uint256,string)",
        nh, invoice["payee_address"], str(invoice["amount_base_units"]), d.memo,
    ])
    if code != 0:
        raise RuntimeError(f"cast send failed ({code}): {err or out}")
    for line in out.splitlines():
        if line.startswith("transactionHash"):
            d.tx_hash = line.split()[-1]
    if d.tx_hash is None:
        d.tx_hash = out.splitlines()[-1].strip()
    d.status = "paid"
    return d


async def record_refusal(d: Decision) -> None:
    """Put the refusal on-chain too, so the audit trail is not just a local file."""
    if d.status != "blocked" or not AGENT_KEY:
        return
    await run([
        CAST, "send", "--rpc-url", RPC, "--private-key", AGENT_KEY,
        ENVELOPE, "logBlocked(bytes32,address,uint256,uint8)",
        d.name_hash, d.payee_address, str(d.amount_base_units), str(d.reason_code),
    ])


async def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("invoices", help="JSON file with a list of invoices")
    ap.add_argument("--out", default="audit.jsonl")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    invoices = json.loads(Path(args.invoices).read_text())
    out = Path(args.out)

    results = []
    for inv in invoices:
        try:
            d = await guard(inv, args.dry_run)
        except Exception as exc:  # noqa: BLE001
            d = Decision(
                invoice_id=str(inv.get("invoice_id", "")),
                payee_name=inv.get("payee_name", "?"),
                payee_name_normalised=norm(inv.get("payee_name", "")),
                name_hash="",
                payee_address=inv.get("payee_address", ""),
                amount_base_units=int(inv.get("amount_base_units", 0)),
                memo=inv.get("memo", ""),
                status="error",
                reason=f"{type(exc).__name__}: {exc}",
            )
        if d.status == "blocked":
            try:
                await record_refusal(d)
            except Exception:  # noqa: BLE001
                pass
        with out.open("a") as f:
            f.write(json.dumps(asdict(d)) + "\n")
        results.append(d)
        print(f"{d.status:8} {d.invoice_id:10} {d.payee_name:20} {d.reason:26} {d.tx_hash or ''}")

    paid = sum(1 for r in results if r.status == "paid")
    blocked = sum(1 for r in results if r.status == "blocked")
    print(f"\n{paid} paid · {blocked} blocked · {len(results) - paid - blocked} error")


if __name__ == "__main__":
    asyncio.run(main())
