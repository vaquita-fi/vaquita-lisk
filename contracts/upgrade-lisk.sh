source .env

forge script script/UpgradeVaquitaPool.s.sol:UpgradeVaquitaPoolScript \
 --rpc-url $RPC_URL \
 --etherscan-api-key $ETHERSCAN_API_KEY \
 --private-key $PRIVATE_KEY \
 --broadcast \
 --verify \
 --sig "run(address,address,address)" \
 0x5B27D529744b9FA94565886d67dF6E5737211BD2 \
 0xfA95214EA8195e9D256Bb18adF0F56b3dEc66FaE \
 0xfc4fc4bc854d5db7048b69eb036ef5c21046e9c3