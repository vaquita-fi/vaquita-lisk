import * as ethers from "ethers";
import { Mnemonic, Wallet } from "ethers";
import dotenv from "dotenv";
dotenv.config();

const ERC20_ABI = [
    "function approve(address spender, uint256 amount) returns (bool)"
];

const setup = async () => {

    const RPC_URL = process.env.RPC_URL;
    const EXPLORER_BASE_URL = process.env.EXPLORER_BASE_URL;
    const TOKEN_A_ADDRESS = process.env.TOKEN_A_ADDRESS;
    const PRIVATE_KEY = process.env.PRIVATE_KEY;
    const VAQUITA_POOL_ADDRESS = process.env.VAQUITA_POOL_ADDRESS;

    if (!PRIVATE_KEY) {
        throw new Error("PRIVATE_KEY not found in .env file");
    }

    if (!VAQUITA_POOL_ADDRESS) {
        throw new Error("VAQUITA_POOL_ADDRESS not found in .env file");
    }

    const provider = new ethers.JsonRpcProvider(RPC_URL);
    const signer = new Wallet(PRIVATE_KEY, provider);

    // 1. Set balance of signer to 1 ETH
    console.log("Setting virtual network ...");
    await provider.send("tenderly_setBalance", [
        signer.address,
        "0xDE0B6B3A7640000"
    ]);
    console.log("Set balance of", signer.address, "to 1 ETH");

    // // 2. Set balance of signer to 100000 of Token A
    await provider.send("tenderly_setErc20Balance", [
        TOKEN_A_ADDRESS,
        signer.address,
        "0xDE0B6B3A7640000" // 100000 of Token A
    ]);
    console.log("Set balance of", signer.address, "to 100000 of Token A");

    // 3. Approve signer to spend 100000 of Token A
    const tokenA = new ethers.Contract(TOKEN_A_ADDRESS, ERC20_ABI, signer);
    await tokenA.approve(VAQUITA_POOL_ADDRESS, ethers.parseUnits("1000000000000000000", 6));
    console.log("Approved signer to spend 1000000000000000000 of Token A");
}

setup().catch(e => {
    console.error(e);
    process.exitCode = 1;
});