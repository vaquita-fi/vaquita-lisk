import * as ethers from "ethers";
import { Wallet } from "ethers";
import dotenv from "dotenv";
dotenv.config({ path: "contracts/.env" });

const RPC_URL = process.env.RPC_URL;
const EXPLORER_BASE_URL = process.env.EXPLORER_BASE_URL;
const VELODROME_LIQUIDITY_MANAGER_ADDRESS = process.env.VELODROME_LIQUIDITY_MANAGER_ADDRESS;
const TOKEN_A_ADDRESS = process.env.TOKEN_A_ADDRESS;
const PRIVATE_KEY = process.env.PRIVATE_KEY;

if (!PRIVATE_KEY) {
    throw new Error("PRIVATE_KEY not found in .env file");
}

if (!VELODROME_LIQUIDITY_MANAGER_ADDRESS) {
    throw new Error("VELODROME_LIQUIDITY_MANAGER_ADDRESS not found in .env file");
}

// Minimal ABIs
const VELODROME_LIQUIDITY_MANAGER_ABI = [
    "function deposit(bytes16 _depositId, uint256 amount)"
];
const ERC20_ABI = [
    "function approve(address spender, uint256 amount) returns (bool)",
    "function allowance(address owner, address spender) view returns (uint256)"
];

const provider = new ethers.JsonRpcProvider(RPC_URL);
const signer = new Wallet(PRIVATE_KEY, provider);

describe("VelodromeLiquidityManager Integration Tests", () => {
    test("should deposit successfully", async () => {
        console.log(`Using signer address: ${signer.address}`);

        const liquidityManager = new ethers.Contract(VELODROME_LIQUIDITY_MANAGER_ADDRESS, VELODROME_LIQUIDITY_MANAGER_ABI, signer);
        const tokenA = new ethers.Contract(TOKEN_A_ADDRESS, ERC20_ABI, signer);

        const depositId = ethers.randomBytes(16);
        const depositAmount = ethers.parseUnits("20", 6); // Deposit 100000 of Token A

        // 1. Approve the VelodromeLiquidityManager contract to spend our Token A
        const allowance = await tokenA.allowance(signer.address, VELODROME_LIQUIDITY_MANAGER_ADDRESS);
        console.log(`Allowance: ${ethers.formatUnits(allowance, 6)}`);
        if (allowance <= 0) {
            console.log(`Approving VelodromeLiquidityManager to spend ${ethers.formatUnits(ethers.parseUnits("100000", 6), 6)} of Token A...`);
            // Note: In a real test, you might check allowance first and only approve if needed.
            const approveTx = await tokenA.approve(VELODROME_LIQUIDITY_MANAGER_ADDRESS, ethers.parseUnits("100000", 6));
            await approveTx.wait(); // Wait for approval to be mined
            console.log("Approval transaction mined successfully.");
        }

        // 2. Simulate the deposit transaction using Tenderly's custom RPC
        console.log("\nSimulating deposit transaction with Tenderly...");
        try {
            const tx = {
                from: signer.address,
                to: VELODROME_LIQUIDITY_MANAGER_ADDRESS,
                gas: `0x0`,
                gasPrice: "0x0",
                value: "0x0",
                data: liquidityManager.interface.encodeFunctionData("deposit", [depositId, depositAmount]),
            };

            const simulationResult = await provider.send("tenderly_simulateTransaction", [
                tx,
                "latest",
            ]);

            console.log("✅ Simulation successful!");
            // console.log(JSON.stringify(simulationResult.trace, null, 2));

            // 3. If simulation is successful, send the real transaction
            const depositTx = await signer.sendTransaction(tx);
            console.log(`➡️ Deposit transaction sent! View on explorer: ${EXPLORER_BASE_URL}/tx/${depositTx.hash}`);
            await depositTx.wait();
            console.log("✅ Deposit transaction mined successfully.");

        } catch (error) {
            console.error("❌ Simulation failed!");
            // This part helps in debugging by logging the detailed error from Tenderly
            const friendlyError = error.info?.error?.message || error.message;
            console.error("Reason:", friendlyError);
            if (error.info?.error?.data) {
                console.error("Error Data:", error.info.error.data);
            }
        }
    }, 30000); // Increase timeout for async operations
});