source .env

set -e

LIQUIDITY_MANAGER=$(
forge script script/VelodromeLiquidityManagerProxy.s.sol:VelodromeLiquidityManagerProxyScript \
 --rpc-url $RPC_URL \
 --etherscan-api-key $ETHERSCAN_API_KEY \
 --private-key $PRIVATE_KEY \
 --broadcast \
 --verifier blockscout \
 --verifier-url 'https://blockscout.lisk.com/api/' \
 --verify \
 --json
)
echo "Deployed Liquidity Manager at: $LIQUIDITY_MANAGER"

forge script script/DeployVaquitaPoolLisk.s.sol:DeployVaquitaPoolProxyScript \
 --rpc-url $RPC_URL \
 --etherscan-api-key $ETHERSCAN_API_KEY \
 --private-key $PRIVATE_KEY \
 --broadcast \
 --verifier blockscout \
 --verifier-url 'https://blockscout.lisk.com/api/' \
 --verify \
 --sig "run(address)" \
 0x6098d9e60F67d3c8515e08fCBc01E341B8821332
echo "Deployed Vaquita Pool at: $VAQUITA_POOL"