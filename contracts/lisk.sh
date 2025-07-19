source .env

set -e

LIQUIDITY_MANAGER=$(
forge script script/VelodromeLiquidityManagerProxy.s.sol:VelodromeLiquidityManagerProxyScript \
 --rpc-url $RPC_URL \
 --etherscan-api-key $ETHERSCAN_API_KEY \
 --private-key $PRIVATE_KEY \
 --broadcast \
 --verify \
 --json | jq -r '.returns | .[] | select(.name=="result") | .value'
 )
echo "Deployed Liquidity Manager at: $LIQUIDITY_MANAGER"

forge script script/DeployVaquitaPoolLisk.s.sol:DeployVaquitaPoolProxyScript \
 --rpc-url $RPC_URL \
 --etherscan-api-key $ETHERSCAN_API_KEY \
 --private-key $PRIVATE_KEY \
 --broadcast \
 --verify \
 --sig "run(address)" \
 $LIQUIDITY_MANAGER
echo "Deployed Vaquita Pool at: $VAQUITA_POOL"