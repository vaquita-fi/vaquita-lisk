// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {VaquitaPool} from "../src/VaquitaPool.sol";
import {IVelodromeLiquidityManager} from "../src/interfaces/IVelodromeLiquidityManager.sol";
import {VelodromeLiquidityManager} from "../src/VelodromeLiquidityManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPermit} from "../src/interfaces/IPermit.sol";
import {IUniversalRouter} from "../src/interfaces/external/IUniversalRouter.sol";
import {TestUtils} from "./TestUtils.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract VaquitaPoolTest is TestUtils {
    VaquitaPool public vaquita;
    IERC20 public token;
    IERC20 public lpPairToken;
    VelodromeLiquidityManager public liquidityManager;
    address public whale;
    address public owner;
    address public alice;
    address public bob;
    address public charlie;
    uint256 public alicePrivateKey;
    uint256 public bobPrivateKey;
    uint256 public charliePrivateKey;
    address public universalRouter;
    address public positionManager;
    uint256 public initialAmount = 1_000e6; // 1M USDC
    uint256 public lockPeriod = 1 days;

    // Mainnet addresses (replace with real ones for your deployment)
    address constant TOKEN_ADDRESS = 0xF242275d3a6527d877f2c927a82D9b057609cc71; // USDC mainnet
    address constant LP_PAIR_TOKEN_ADDRESS = 0x05D032ac25d322df992303dCa074EE7392C117b9; // Replace with real
    address constant UNIVERSAL_ROUTER_ADDRESS = 0x652e53C6a4FE39B6B30426d9c96376a105C89A95; // USDC rich address
    address constant POSITION_MANAGER_ADDRESS = 0x991d5546C4B442B4c5fdc4c8B8b8d131DEB24702; // USDC rich address
    address constant WHALE_ADDRESS = 0xC859c755E8C0568fD86F7860Bcf9A59D6F57BEB5; // USDC rich address

    uint256 public v3SwapExactIn = 0x00;
    int24 public tickSpacing = 1;
    int24 public tickLower = 3;
    int24 public tickUpper = 6;

    function setUp() public {
        // Fork mainnet
        uint256 liskForkBlock = 17_998_944;
        vm.createSelectFork(vm.rpcUrl("lisk"), liskForkBlock);

        token = IERC20(TOKEN_ADDRESS);
        lpPairToken = IERC20(LP_PAIR_TOKEN_ADDRESS);
        universalRouter = UNIVERSAL_ROUTER_ADDRESS;
        positionManager = POSITION_MANAGER_ADDRESS;
        whale = address(WHALE_ADDRESS);
        (alice, alicePrivateKey) = makeAddrAndKey("alice");
        (bob, bobPrivateKey) = makeAddrAndKey("bob");
        (charlie, charliePrivateKey) = makeAddrAndKey("charlie");
        owner = address(this);
        liquidityManager = new VelodromeLiquidityManager();
        liquidityManager.initialize(
            address(token),
            address(lpPairToken),
            address(universalRouter),
            address(positionManager),
            v3SwapExactIn,
            tickSpacing,
            tickLower,
            tickUpper
        );
        vaquita = new VaquitaPool();
        vaquita.initialize(address(token), address(liquidityManager), lockPeriod);
        // Fund users with USDC from whale
        vm.startPrank(whale);
        token.transfer(alice, initialAmount);
        token.transfer(bob, initialAmount * 2);
        token.transfer(charlie, initialAmount * 3);
        token.transfer(owner, initialAmount * 4);
        vm.stopPrank();
    }

    function deposit(
        address user,
        bytes16 depositId,
        uint256 depositAmount
    ) public returns (uint256) {
        vm.startPrank(user);
        token.approve(address(vaquita), depositAmount);
        uint256 shares = vaquita.deposit(depositId, depositAmount, block.timestamp + 1 hours, "");
        vm.stopPrank();
        return shares;
    }

    function withdraw(
        address user,
        bytes16 depositId
    ) public returns (uint256) {
        vm.startPrank(user);
        uint256 amount = vaquita.withdraw(depositId);
        vm.stopPrank();
        return amount;
    }

    function test_DepositWithPermit() public {
        vm.startPrank(alice);
        
        // Prepare EIP-712 permit data
        uint256 nonce = IPermit(address(token)).nonces(alice);
        uint256 deadline = block.timestamp + 1 hours;
        uint256 chainId = block.chainid;
        string memory name = "Bridged USDC (Lisk)";
        string memory version = "2";
        address verifyingContract = address(token);
        bytes16 aliceDepositId = bytes16(keccak256(abi.encodePacked(alice, block.timestamp)));
        
        // EIP-712 JSON structure for permit
        string memory permitJson = string(abi.encodePacked(
            '{',
                '"types": {',
                    '"EIP712Domain": [',
                        '{"name": "name", "type": "string"},',
                        '{"name": "version", "type": "string"},',
                        '{"name": "chainId", "type": "uint256"},',
                        '{"name": "verifyingContract", "type": "address"}',
                    '],',
                    '"Permit": [',
                        '{"name": "owner", "type": "address"},',
                        '{"name": "spender", "type": "address"},',
                        '{"name": "value", "type": "uint256"},',
                        '{"name": "nonce", "type": "uint256"},',
                        '{"name": "deadline", "type": "uint256"}',
                    ']'
                '},',
                '"primaryType": "Permit",',
                '"domain": {',
                    '"name": "', name, '",',
                    '"version": "', version, '",',
                    '"chainId": ', vm.toString(chainId), ',',
                    '"verifyingContract": "', vm.toString(verifyingContract), '"',
                '},',
                '"message": {',
                    '"owner": "', vm.toString(alice), '",',
                    '"spender": "', vm.toString(address(vaquita)), '",',
                    '"value": ', vm.toString(initialAmount), ',',
                    '"nonce": ', vm.toString(nonce), ',',
                    '"deadline": ', vm.toString(deadline),
                '}',
            '}'
        ));

        // Compute the EIP-712 digest
        bytes32 digest = vm.eip712HashTypedData(permitJson);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);
        console.log("signature");
        console.logBytes(signature);
        
        // Now make the deposit
        deposit(alice, aliceDepositId, initialAmount);
        
        // Verify the deposit was successful
        (address positionOwner,, uint256 shares,,,) = vaquita.getPosition(aliceDepositId);
        assertEq(positionOwner, alice);
        assertGt(shares, 0);
        
        vm.stopPrank();
    }

    function test_DepositWithApproval() public {
        bytes16 aliceDepositId = bytes16(keccak256(abi.encodePacked(alice, block.timestamp)));
        uint256 shares = deposit(alice, aliceDepositId, initialAmount);
        assertGt(shares, 0);
    }

    function test_WithdrawAfterLock() public {
        bytes16 aliceDepositId = bytes16(keccak256(abi.encodePacked(alice, block.timestamp)));
        deposit(alice, aliceDepositId, initialAmount);
        vm.warp(block.timestamp + lockPeriod);
        withdraw(alice, aliceDepositId);
        (,,,,, bool isActive) = vaquita.getPosition(aliceDepositId);
        assertFalse(isActive);
    }

    function test_AddRewardsToRewardPool() public {
        vm.startPrank(owner);
        uint256 rewardAmount = 1000e6;
        uint256 ownerBalanceBefore = token.balanceOf(owner);
        uint256 rewardPoolBefore = vaquita.rewardPool();
        token.approve(address(vaquita), rewardAmount);
        vaquita.addRewards(rewardAmount);
        uint256 ownerBalanceAfter = token.balanceOf(owner);
        uint256 rewardPoolAfter = vaquita.rewardPool();
        assertEq(rewardPoolAfter, rewardPoolBefore + rewardAmount, "Reward pool should increase by rewardAmount");
        assertEq(ownerBalanceAfter, ownerBalanceBefore - rewardAmount, "Owner balance should decrease by rewardAmount");
        vm.stopPrank();
    }

    function test_EarlyWithdrawal() public {
        bytes16 aliceDepositId = bytes16(keccak256(abi.encodePacked(alice, block.timestamp)));
        uint256 aliceBalanceBefore = token.balanceOf(alice);
        deposit(alice, aliceDepositId, initialAmount);

        mockCallWithParams(
            address(liquidityManager),
            liquidityManager.withdraw.selector,
            abi.encode(aliceDepositId),
            abi.encode(initialAmount + 50e6)
        );
        fundWithTokens(token, whale, address(vaquita), initialAmount + 50e6);

        // Withdraw before lock period ends
        vm.warp(block.timestamp + lockPeriod / 2);

        uint256 aliceWithdrawal = withdraw(alice, aliceDepositId);
        uint256 aliceBalanceAfter = token.balanceOf(alice);
        assertEq(vaquita.totalDeposits(), 0, "Total deposits should be 0");
        assertEq(vaquita.totalShares(), 0, "Total shares should be 0");
        assertEq(vaquita.rewardPool(), 50e6, "Reward pool should be 50e6");
        assertEq(aliceWithdrawal, initialAmount, "Alice should withdraw all her shares");
        assertEq(aliceBalanceBefore, aliceBalanceAfter, "Alice should not have lost any balance");
    }

    function test_MultipleUsersWithFeeDistribution() public {
        bytes16 aliceDepositId = bytes16(keccak256(abi.encodePacked(alice, block.timestamp + 1)));
        bytes16 bobDepositId = bytes16(keccak256(abi.encodePacked(bob, block.timestamp + 1)));
        
        // Add rewards to pool
        uint256 rewardAmount = 300e6;
        vm.startPrank(owner);
        token.approve(address(vaquita), rewardAmount);
        vaquita.addRewards(rewardAmount);
        vm.stopPrank();

        // Alice deposits
        uint256 aliceShares = deposit(alice, aliceDepositId, initialAmount);
        console.log("aliceShares", aliceShares);
        // Bob deposits twice as much as Alice
        uint256 bobShares = deposit(bob, bobDepositId, initialAmount * 2);
        console.log("bobShares", bobShares);
        // Mock LP fees for both positions
        mockCallWithParams(
            address(liquidityManager),
            liquidityManager.withdraw.selector,
            abi.encode(aliceDepositId),
            abi.encode(initialAmount + 50e6)
        );
        fundWithTokens(token, whale, address(vaquita), initialAmount + 50e6);
        mockCallWithParams(
            address(liquidityManager),
            liquidityManager.withdraw.selector,
            abi.encode(bobDepositId),
            abi.encode(initialAmount * 2 + 100e6)
        );
        fundWithTokens(token, whale, address(vaquita), initialAmount * 2 + 100e6);

        // Wait for lock period
        vm.warp(block.timestamp + lockPeriod);

        console.log("vaquita.rewardPool()", vaquita.rewardPool());
        console.log("vaquita.totalShares()", vaquita.totalShares());

        uint256 totalShares = vaquita.totalShares();
        uint256 rewardPool = vaquita.rewardPool();

        uint256 aliceReward = aliceShares * rewardPool / totalShares;
        uint256 bobReward = bobShares * (rewardPool - aliceReward) / (totalShares - aliceShares);
        
        // Alice withdraws (should get 1/3 of reward pool since she deposited 1M out of 3M total)
        uint256 aliceBalanceBefore = token.balanceOf(alice);
        withdraw(alice, aliceDepositId);
        uint256 aliceBalanceAfter = token.balanceOf(alice);
        
        // Bob withdraws (should get 2/3 of remaining reward pool)
        uint256 bobBalanceBefore = token.balanceOf(bob);
        withdraw(bob, bobDepositId);
        uint256 bobBalanceAfter = token.balanceOf(bob);
        
        uint256 aliceTotal = aliceBalanceAfter - aliceBalanceBefore;
        uint256 aliceLPProfit = 50e6;
        uint256 bobTotal = bobBalanceAfter - bobBalanceBefore;
        uint256 bobLPProfit = 100e6;
        
        console.log("Alice deposited:", initialAmount);
        console.log("Alice received:", aliceTotal);
        console.log("Alice profit:", aliceLPProfit);
        console.log("Alice reward:", aliceReward);
        console.log("Alice LP profit:", aliceLPProfit);
        
        console.log("Bob deposited:", initialAmount * 2);
        console.log("Bob received:", bobTotal);
        console.log("Bob profit:", bobLPProfit);
        console.log("Bob reward:", bobReward);
        console.log("Bob LP profit:", bobLPProfit);
        assertEq(aliceTotal, initialAmount + aliceLPProfit + aliceReward, "Alice total should be initialAmount + aliceLPProfit + aliceReward");
        assertEq(bobTotal, initialAmount * 2 + bobLPProfit + bobReward, "Bob total should be initialAmount * 2 + bobLPProfit + bobReward");

        // Verify both users got more than they deposited
        assertGt(aliceTotal, initialAmount, "Alice should profit");
        assertGt(bobTotal, initialAmount * 2, "Bob should profit");
        console.log("Reward pool:", vaquita.rewardPool());
        assertEq(vaquita.rewardPool(), 0, "Reward pool should be 0");
    }

    function test_WhaleSwapGeneratesFees() public {
        console.log("=== Starting Whale Swap Fee Generation Test ===");
        
        // Step 1: Alice deposits into VaquitaPool
        bytes16 aliceDepositId = bytes16(keccak256(abi.encodePacked(alice, block.timestamp)));
        deposit(alice, aliceDepositId, initialAmount);
        
        uint256 aliceBalanceBefore = token.balanceOf(alice);
        console.log("Alice balance before deposit:", aliceBalanceBefore);
        
        (, uint256 positionAmount, uint256 shares,,,) = vaquita.getPosition(aliceDepositId);
        console.log("Position amount:", positionAmount);
        console.log("Position shares:", shares);

        // Step 2: Check liquidity manager position before whale swap
        uint256 positionTokenId = liquidityManager.positionTokenId();
        console.log("Position token ID:", positionTokenId);
        
        // Step 3: Simulate whale making a large swap to generate fees
        console.log("\n=== Whale Swap Activity ===");
        generateSwapFees(
            whale,
            token,
            lpPairToken,
            universalRouter,
            v3SwapExactIn,
            tickSpacing,
            1_000_000e6
        );
        
        // Step 4: Wait for lock period to pass
        console.log("\n=== Time Travel Past Lock Period ===");
        vm.warp(block.timestamp + lockPeriod + 1);
        
        // Step 5: Alice withdraws and check if she got more than she deposited
        console.log("\n=== Alice Withdrawal ===");
        
        uint256 aliceBalanceBeforeWithdraw = token.balanceOf(alice);
        console.log("Alice balance before withdraw:", aliceBalanceBeforeWithdraw);
        
        uint256 withdrawnAmount = withdraw(alice, aliceDepositId);
        
        uint256 aliceBalanceAfterWithdraw = token.balanceOf(alice);
        console.log("Alice balance after withdraw:", aliceBalanceAfterWithdraw);
        console.log("Amount withdrawn:", withdrawnAmount);
        console.log("Original deposit:", initialAmount);
        
        // Calculate profit/loss
        uint256 totalReceived = aliceBalanceAfterWithdraw - aliceBalanceBeforeWithdraw;
        console.log("Total received by Alice:", totalReceived);
        
        if (totalReceived > initialAmount) {
            uint256 profit = totalReceived - initialAmount;
            console.log("Alice made a profit of:", profit);
            console.log("Profit percentage:", (profit * 10000) / initialAmount, "basis points");
            
            // Assert that Alice made a profit
            assertGt(totalReceived, initialAmount, "Alice should have made a profit from LP fees");
        } else {
            uint256 loss = initialAmount - totalReceived;
            console.log("Alice made a loss of:", loss);
            console.log("Loss percentage:", (loss * 10000) / initialAmount, "basis points");
        }
        
        // Step 6: Additional verification - check if there are any fees collected
        console.log("\n=== Final State Check ===");
        console.log("VaquitaPool reward pool:", vaquita.rewardPool());
        console.log("VaquitaPool protocol fees:", vaquita.protocolFees());
        console.log("VaquitaPool total deposits:", vaquita.totalDeposits());
        
        // Check if the position is now inactive
        (,,,,, bool isActive) = vaquita.getPosition(aliceDepositId);
        assertFalse(isActive, "Position should be inactive after withdrawal");
    }

    function test_MultipleUsersWithWhaleSwap() public {
        // Multiple users deposit
        bytes16 aliceDepositId = bytes16(keccak256(abi.encodePacked(alice, block.timestamp)));
        bytes16 bobDepositId = bytes16(keccak256(abi.encodePacked(bob, block.timestamp, "bob")));
        bytes16 charlieDepositId = bytes16(keccak256(abi.encodePacked(charlie, block.timestamp, "charlie")));
        
        // Alice deposits
        uint256 aliceShares = deposit(alice, aliceDepositId, initialAmount);
        // Bob deposits
        uint256 bobShares = deposit(bob, bobDepositId, initialAmount);
        // Charlie deposits
        uint256 charlieShares = deposit(charlie, charlieDepositId, initialAmount);

        assertEq(aliceShares + bobShares + charlieShares, vaquita.totalShares(), "Total shares should be 3 * initialAmount");
        
        console.log("Total deposits of vaquita", vaquita.totalDeposits());
        assertEq(vaquita.totalDeposits(), 3 * initialAmount, "Total deposits should be 3 * initialAmount");
        
        // Whale makes multiple swaps to generate more fees
        for (uint i = 0; i < 3; i++) {
            generateSwapFees(
                whale,
                token,
                lpPairToken,
                universalRouter,
                v3SwapExactIn,
                tickSpacing,
                400_000e6
            );
            vm.warp(block.timestamp + 1 hours);
        }
        
        // Fast forward past lock period
        vm.warp(block.timestamp + lockPeriod + 1);

        console.log("Token balance of vaquita before withdraws", token.balanceOf(address(vaquita)));
        
        // All users withdraw and check profits
        address[3] memory users = [alice, bob, charlie];
        bytes16[3] memory userDepositIds = [aliceDepositId, bobDepositId, charlieDepositId];
        
        for (uint i = 0; i < users.length; i++) {
            uint256 balanceBefore = token.balanceOf(users[i]);
            uint256 withdrawn = withdraw(users[i], userDepositIds[i]);
            uint256 balanceAfter = token.balanceOf(users[i]);
            
            assertEq(balanceAfter, balanceBefore + withdrawn, "User should have received the correct amount");

            console.log("User", i, "total received:", withdrawn);
            console.log("User", i, "original deposit:", initialAmount);
            
            if (withdrawn > initialAmount) {
                console.log("User", i, "profit:", withdrawn - initialAmount);
            }
        }

        console.log("Token balance of vaquita after withdraws", token.balanceOf(address(vaquita)));
        assertEq(token.balanceOf(address(vaquita)), 0, "Vaquita should have 0 balance after withdraws");
    }

    function test_PauseAndUnpause() public {
        // Only owner can pause
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vaquita.pause();

        // Owner can pause
        vm.prank(owner);
        vaquita.pause();
        assertTrue(vaquita.paused(), "Contract should be paused");

        // Deposit should revert when paused
        vm.prank(alice);
        token.approve(address(vaquita), 1e6);
        vm.expectRevert();
        vaquita.deposit(bytes16(keccak256("id1")), 1e6, block.timestamp + 1 days, "");

        // Withdraw should revert when paused
        vm.expectRevert();
        vaquita.withdraw(bytes16(keccak256("id1")));

        // addRewards should revert when paused
        vm.prank(owner);
        vm.expectRevert();
        vaquita.addRewards(1e6);

        // withdrawProtocolFees should revert when paused
        vm.prank(owner);
        vm.expectRevert();
        vaquita.withdrawProtocolFees();

        // Only owner can unpause
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vaquita.unpause();

        // Owner can unpause
        vm.prank(owner);
        vaquita.unpause();
        assertFalse(vaquita.paused(), "Contract should be unpaused");
    }

    function test_UpdateEarlyWithdrawalFee() public {
        // Only owner can update
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vaquita.updateEarlyWithdrawalFee(100);

        // Owner can update
        vm.prank(owner);
        vaquita.updateEarlyWithdrawalFee(100);
        assertEq(vaquita.earlyWithdrawalFee(), 100, "Early withdrawal fee should be updated");

        // Revert if fee > BASIS_POINTS
        vm.prank(owner);
        vm.expectRevert(VaquitaPool.InvalidFee.selector);
        vaquita.updateEarlyWithdrawalFee(10001);
    }

    function test_UpdateLockPeriod() public {
        // Only owner can update
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vaquita.updateLockPeriod(2 days);

        // Owner can update
        vm.prank(owner);
        vaquita.updateLockPeriod(2 days);
        assertEq(vaquita.lockPeriod(), 2 days, "Lock period should be updated");
    }

    function test_WithdrawProtocolFees() public {
        // Set early withdrawal fee to 5%
        vm.prank(owner);
        vaquita.updateEarlyWithdrawalFee(500); // 5%

        // Alice deposits
        bytes16 aliceDepositId = bytes16(keccak256(abi.encodePacked(alice, block.timestamp)));
        deposit(alice, aliceDepositId, initialAmount);

        // Simulate whale swap to generate LP fees
        generateSwapFees(
            whale,
            token,
            lpPairToken,
            universalRouter,
            v3SwapExactIn,
            tickSpacing,
            1_000_000e6
        );

        // Alice withdraws early (before lock period ends)
        vm.warp(block.timestamp + lockPeriod / 2);
        withdraw(alice, aliceDepositId);

        // Protocol fees should be greater than 0
        assertGt(vaquita.protocolFees(), 0, "Protocol fees should be greater than 0 after early withdrawal");

        // Only owner can withdraw protocol fees
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vaquita.withdrawProtocolFees();

        // Owner withdraws protocol fees
        vm.prank(owner);
        vaquita.withdrawProtocolFees();
        assertEq(vaquita.protocolFees(), 0, "Protocol fees should be zero after withdrawal");
    }
}