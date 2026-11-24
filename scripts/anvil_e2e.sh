#!/usr/bin/env bash
# End-to-end proof on a local anvil node: deploy, wire a session, run the agent.
# Anvil's default accounts are used so the demo is reproducible byte for byte.
set -euo pipefail

RPC=http://127.0.0.1:8545
ORDER=sort

K_OWNER=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
A_OWNER=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
K_PAYEE=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
A_PAYEE=0x70997970C51812dc3A010C7d01b50e0d17dc79C8
K_TOKO=0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6
A_TOKO=0x90F79bf6EB2c4f870365E785982E1f101E93b906
K_AGENT=0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a
A_AGENT=0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65

parse_addr() { grep -oE 'Deployed to: 0x[0-9a-fA-F]{40}' | awk '{print $3}'; }

echo "── deploy ─────────────────────────────────────────"
TOKEN=$(forge create test/Envelope.t.sol:MockTUSD8 --rpc-url $RPC --private-key $K_OWNER --broadcast 2>&1 | parse_addr)
REGISTRY=$(forge create src/PayeeRegistry.sol:PayeeRegistry --rpc-url $RPC --private-key $K_OWNER --broadcast 2>&1 | parse_addr)
ENVELOPE=$(forge create src/SpendEnvelope.sol:SpendEnvelope --rpc-url $RPC --private-key $K_OWNER \
  --broadcast --constructor-args "$TOKEN" "$REGISTRY" 2>&1 | parse_addr)
echo "token    $TOKEN"
echo "registry $REGISTRY"
echo "envelope $ENVELOPE"

echo "── fund ───────────────────────────────────────────"
cast send --rpc-url $RPC --private-key $K_OWNER $TOKEN "mint(address,uint256)" $A_OWNER 100000000 >/dev/null
cast send --rpc-url $RPC --private-key $K_OWNER $TOKEN "approve(address,uint256)" $ENVELOPE 100000000 >/dev/null
cast send --rpc-url $RPC --private-key $K_OWNER $ENVELOPE "fund(uint256)" 50000000 >/dev/null
echo "envelope balance: $(cast call --rpc-url $RPC $TOKEN 'balanceOf(address)(uint256)' $ENVELOPE)"

echo "── register payees ────────────────────────────────"
H_SRI=$(cast keccak "warung bu sri")
H_TOKO=$(cast keccak "toko kopi andalas")
cast send --rpc-url $RPC --private-key $K_PAYEE $REGISTRY "register(bytes32,string)" $H_SRI "Warung Bu Sri" >/dev/null
cast send --rpc-url $RPC --private-key $K_TOKO  $REGISTRY "register(bytes32,string)" $H_TOKO "Toko Kopi Andalas" >/dev/null
echo "confirm(sri, payee)  = $(cast call --rpc-url $RPC $REGISTRY 'confirm(bytes32,address)(bool)' $H_SRI $A_PAYEE)"
echo "confirm(sri, impostor) = $(cast call --rpc-url $RPC $REGISTRY 'confirm(bytes32,address)(bool)' $H_SRI 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC)"

echo "── open session ───────────────────────────────────"
EXPIRY=$(( $(date +%s) + 86400 ))
cast send --rpc-url $RPC --private-key $K_OWNER $ENVELOPE \
  "createSession(address,uint64,uint128,uint128,bool)" $A_AGENT $EXPIRY 5000000 10000000 true >/dev/null
echo "perTxCap=5 tUSD8  dailyCap=10 tUSD8  expiry=$EXPIRY  agent=$A_AGENT"

cat > /root/aevum-payguard/.anvil.env <<EOF
AEVUM_RPC=$RPC
TUSD8_ADDRESS=$TOKEN
REGISTRY_ADDRESS=$REGISTRY
ENVELOPE_ADDRESS=$ENVELOPE
AGENT_ADDRESS=$A_AGENT
AGENT_PRIVATE_KEY=$K_AGENT
EOF
echo "wired → /root/aevum-payguard/.anvil.env"
