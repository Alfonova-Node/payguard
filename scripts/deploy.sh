#!/usr/bin/env bash
# Deploy the two contracts on Aevum Testnet (chain 44005) and wire the session.
#
# Requires: forge/cast in PATH, .env filled with AEVUM_RPC, TUSD8_ADDRESS and
# OWNER_PRIVATE_KEY. AGENT_ADDRESS and PAYEE keys are passed in, never stored.
set -euo pipefail

: "${AEVUM_RPC:?set AEVUM_RPC}"
: "${TUSD8_ADDRESS:?set TUSD8_ADDRESS}"
: "${OWNER_PRIVATE_KEY:?set OWNER_PRIVATE_KEY}"

echo "→ deploying PayeeRegistry"
REGISTRY=$(forge create src/PayeeRegistry.sol:PayeeRegistry \
  --rpc-url "$AEVUM_RPC" --private-key "$OWNER_PRIVATE_KEY" --broadcast --json | jq -r .deployedTo)
echo "  registry = $REGISTRY"

echo "→ deploying SpendEnvelope"
ENVELOPE=$(forge create src/SpendEnvelope.sol:SpendEnvelope \
  --rpc-url "$AEVUM_RPC" --private-key "$OWNER_PRIVATE_KEY" \
  --constructor-args "$TUSD8_ADDRESS" "$REGISTRY" --json | jq -r .deployedTo)
echo "  envelope = $ENVELOPE"

echo
echo "Add these to .env:"
echo "REGISTRY_ADDRESS=$REGISTRY"
echo "ENVELOPE_ADDRESS=$ENVELOPE"
