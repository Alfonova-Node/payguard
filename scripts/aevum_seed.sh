#!/usr/bin/env bash
# Seed the live Aevum Testnet demo: register payees, fund the envelope, open a session.
#
# Needs: forge/cast, .env loaded with AEVUM_RPC, TUSD8_ADDRESS, REGISTRY_ADDRESS,
# ENVELOPE_ADDRESS, OWNER_PRIVATE_KEY, AGENT_ADDRESS, and PAYEE_KEY_<N> /
# PAYEE_ADDR_<N> pairs for each payee that registers its own name.
#
# Every payee registers with its OWN key — that is the point of the registry.
set -euo pipefail

: "${AEVUM_RPC:?}" "${TUSD8_ADDRESS:?}" "${REGISTRY_ADDRESS:?}" "${ENVELOPE_ADDRESS:?}"
: "${OWNER_PRIVATE_KEY:?}" "${AGENT_ADDRESS:?}"

PER_TX=${PER_TX:-5000000}      # 5 tUSD8
DAILY=${DAILY:-10000000}       # 10 tUSD8
FUND=${FUND:-50000000}         # 50 tUSD8 into the envelope
EXPIRY=$(( $(date +%s) + ${SESSION_TTL:-604800} ))   # 7 days

send() { cast send --rpc-url "$AEVUM_RPC" "$@" >/dev/null; echo "  ok $3"; }
txhash() { cast send --rpc-url "$AEVUM_RPC" "$@" 2>&1 | grep -oE '0x[0-9a-f]{64}' | head -1; }

echo "→ payees register themselves"
for i in 1 2 3 4 5; do
  pk="PAYEE_KEY_$i"; ad="PAYEE_ADDR_$i"; nm="PAYEE_NAME_$i"
  if [ -n "${!pk:-}" ] && [ -n "${!nm:-}" ]; then
    h=$(cast keccak "$(printf '%s' "${!nm}" | tr '[:upper:]' '[:lower:]' | tr -s ' ')" | xargs)
    echo -n "  ${!nm} → ${!ad} "
    cast send --rpc-url "$AEVUM_RPC" --private-key "${!pk}" \
      "$REGISTRY_ADDRESS" "register(bytes32,string)" "$h" "${!nm}" >/dev/null
    echo "ok"
  fi
done

echo "→ fund envelope with $FUND base units"
cast send --rpc-url "$AEVUM_RPC" --private-key "$OWNER_PRIVATE_KEY" \
  "$TUSD8_ADDRESS" "approve(address,uint256)" "$ENVELOPE_ADDRESS" "$FUND" >/dev/null
echo -n "  funded: "
txhash --private-key "$OWNER_PRIVATE_KEY" "$ENVELOPE_ADDRESS" "fund(uint256)" "$FUND"

echo "→ open agent session (perTx=$PER_TX daily=$DAILY expiry=$EXPIRY)"
txhash --private-key "$OWNER_PRIVATE_KEY" "$ENVELOPE_ADDRESS" \
  "createSession(address,uint64,uint128,uint128,bool)" "$AGENT_ADDRESS" "$EXPIRY" "$PER_TX" "$DAILY" true

echo "→ session on chain:"
cast call --rpc-url "$AEVUM_RPC" "$ENVELOPE_ADDRESS" \
  "sessions(address)(bool,bool,uint64,uint128,uint128,uint128,uint64,uint256,uint256)" "$AGENT_ADDRESS"

echo
echo "run the agent:  python3 agent/guardian.py agent/invoices.example.json"
