# Paket submit — Aevum Builder Challenge #1

Buka `https://dorahacks.io/hackathon/qday/detail` di HP, login (GitHub `Alfonova-Node`),
tekan **Submit / BUIDL**. Tempel isian di bawah ini satu per satu.

---

## Project name

```
PayGuard
```

## Tagline / one-liner

```
Agent payments that cannot pay the wrong person
```

## Track

```
Native AI Assistants
```

## GitHub repository

```
https://github.com/Alfonova-Node/payguard
```

## Video demo

```
https://github.com/Alfonova-Node/payguard/blob/main/docs/PayGuard-demo.mp4
```

Kalau form minta link video yang bisa diputar langsung (YouTube/Drive), bilang ke aku —
aku render ulang atau kamu upload MP4-nya dari `docs/PayGuard-demo.mp4` (3,4 MB).

## Live deployment / demo evidence

```
Aevum Testnet — chain id 44005
tUSD8  0x456569838f1d43009A91ebA4263147Afd7233483 (6 decimals)

PayeeRegistry   0x5246b48c6791F1980f5F0d6b63b74A4940a2c7C8
SpendEnvelope   0xE9960C67813CAD672Afe48d93E5199712f85C529

payee self-registration  https://explorer-test.qday.info/tx/0x0fdca39bdd9f0c32e15214a6aca1269b20fd9be9f244cbffb9203572affb9a57
envelope funded 4 tUSD8  https://explorer-test.qday.info/tx/0x3f5557e7da7a78fce38dbd1f68f95552c4710f0b77c562b471259f3a27bd48ca
session opened           https://explorer-test.qday.info/tx/0xf1172291c56691c5f5f2f6df9dcf4380ac4c1c85d56a8af5e3ba2c388df8bcde
payment 1.5 tUSD8 paid   https://explorer-test.qday.info/tx/0xe547bc31fafe307bed978b417a45da3ae589e06456a11202f3c87d47c2e0e4eb
refusal logged on-chain  https://explorer-test.qday.info/tx/0x7257b7b40d2dd63f7343794aa2594c7f847f055b6197cd528540c3ee0ef2921c
```

## Description (English — untuk juri)

```
An AI agent that can send stablecoin payments but cannot be talked into paying the wrong
party.

Payees register their own name-to-wallet binding on-chain: only the wallet itself can attach
a display name, so neither the contract owner nor the agent can bless someone else's address.
When an invoice arrives with a familiar name but a different wallet, the payment contract
asks the registry, gets a mismatch, and the transfer is never built.

Every spend also runs through a scoped session key: per-transaction cap, daily cap, expiry
and instant revocation. Usage is tracked per (agent, day) rather than per session, so revoking
and re-issuing a session cannot launder a spent cap — a common design slip.

Refusals are written on-chain through logBlocked(), so the audit trail is contract state
rather than a log file the agent could edit. The session struct keeps a permanent
paid/blocked counter.

Deployed and executed on Aevum Testnet: one 1.5 tUSD8 payment settled (block 4,041,545), three
refusals recorded on-chain, 12 Foundry tests passing.

Stack: Solidity 0.8.24 + Foundry, Python asyncio agent driving `cast`, tUSD8 (FiatToken, 6
decimals) on chain 44005.
```

## Kalau ada kolom "technologies"

```
Solidity, Foundry, Python, asyncio, EVM, stablecoin payments, session keys, smart accounts
```

## Kalau ada kolom "team"

```
Solo — Alfonova-Node (https://github.com/Alfonova-Node)
```

## Yang perlu kamu siapkan di HP

- Login DoraHacks pakai GitHub `Alfonova-Node` (akun yang sama saat registrasi)
- Lolos verifikasi "choose all the beds" di HP — di situ kamu manusia, di sini aku cuma bot
- Tempel isian di atas, submit

Setelah submit, kirim ke aku screenshot halaman "submitted" atau URL BUIDL-nya. Aku cek
apakah track, repo, dan bukti tx-nya kebaca benar, lalu kita tandai tanggal 15 Desember
(Demo Day) di kalender.
