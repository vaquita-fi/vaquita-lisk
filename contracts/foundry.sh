source .env

forge script script/VaquitaPool.s.sol:VaquitaPoolScript \
 --rpc-url $RPC_URL \
 --etherscan-api-key $TENDERLY_ACCESS_KEY \
 --private-key $PRIVATE_KEY \
 --verifier-url $VERIFIER_URL \
 --broadcast \
 --legacy

 # Get constructor arguments from the deployment script
 CONSTRUCTOR_ARGS=$(cast abi-encode "constructor(address,address,address,address,uint256,int24,int24,int24)" \
   $(jq -r '.transactions[0].arguments[]' broadcast/VaquitaPool.s.sol/76222/run-latest.json))
 echo $CONSTRUCTOR_ARGS

 # Get deployed contract address
 CONTRACT_ADDRESS=$(jq -r '.transactions[0].contractAddress' broadcast/VaquitaPool.s.sol/76222/run-latest.json)
 echo $CONTRACT_ADDRESS

 # Verify contract
 forge verify-contract \
   --constructor-args $CONSTRUCTOR_ARGS \
   --etherscan-api-key $TENDERLY_ACCESS_KEY \
   --verifier-url $VERIFIER_URL \
   $CONTRACT_ADDRESS \
   src/VaquitaPool.sol:VaquitaPool

