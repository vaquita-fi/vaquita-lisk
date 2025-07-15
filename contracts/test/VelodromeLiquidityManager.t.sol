// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {VelodromeLiquidityManager, Deposit} from "../src/VelodromeLiquidityManager.sol";
import {INonfungiblePositionManager} from "../src/interfaces/external/INonFungiblePositionManager.sol";
import {IUniversalRouter} from "../src/interfaces/external/IUniversalRouter.sol";
import {TestUtils} from "./TestUtils.sol";

contract VelodromeLiquidityManagerTest is Test, TestUtils {
    VelodromeLiquidityManager public liquidityManager;
    IERC20 public tokenA;
    IERC20 public tokenB;
    address public universalRouter;
    address public positionManager;
    address public whale;
    address public owner;

    address public alice;
    address public bob;
    address public charlie;
    address public dave;

    // Real Lisk mainnet addresses from VelodromeLiquidityManager.s.sol
    address constant TOKEN_A_ADDRESS = 0xF242275d3a6527d877f2c927a82D9b057609cc71;
    address constant TOKEN_B_ADDRESS = 0x05D032ac25d322df992303dCa074EE7392C117b9;
    address constant UNIVERSAL_ROUTER_ADDRESS = 0x652e53C6a4FE39B6B30426d9c96376a105C89A95;
    address constant POSITION_MANAGER_ADDRESS = 0x991d5546C4B442B4c5fdc4c8B8b8d131DEB24702;
    address constant TOKEN_A_WHALE = 0xC859c755E8C0568fD86F7860Bcf9A59D6F57BEB5;

    uint8 public v3SwapExactIn = 0x00;
    int24 public tickSpacing = 1;
    int24 public tickLower = 3;
    int24 public tickUpper = 6;

    function setUp() public {
        // Best practice: fork Lisk mainnet here for reproducibility and CI
        // This ensures the fork is always set, regardless of test command arguments
        uint256 liskForkBlock = 17_998_944;
        vm.createSelectFork(vm.rpcUrl("lisk"), liskForkBlock);

        // Assign real contract addresses
        tokenA = IERC20(TOKEN_A_ADDRESS);
        tokenB = IERC20(TOKEN_B_ADDRESS);
        universalRouter = UNIVERSAL_ROUTER_ADDRESS;
        positionManager = POSITION_MANAGER_ADDRESS;
        whale = TOKEN_A_WHALE;
        owner = address(this);

        // Create test users
        alice = address(0xA11CE);
        bob = address(0xB0B);
        charlie = makeAddr("charlie");
        dave = makeAddr("dave");
        // Impersonate whale and transfer TokenA to alice and bob
        uint256 transferAmount = 100_000 * 1e6; // Adjust decimals as needed
        uint256 transferAmount2 = 1_000 * 1e6;
        vm.startPrank(whale);
        tokenA.transfer(alice, transferAmount);
        tokenA.transfer(bob, transferAmount);
        tokenA.transfer(charlie, transferAmount2);
        tokenA.transfer(dave, transferAmount2);
        vm.stopPrank();

        // Deploy VelodromeLiquidityManager with real addresses and parameters
        liquidityManager = new VelodromeLiquidityManager();
        liquidityManager.initialize(
            address(tokenA),
            address(tokenB),
            universalRouter,
            positionManager,
            v3SwapExactIn,
            tickSpacing,
            tickLower,
            tickUpper
        );
    }

    function deposit(
        address user,
        bytes16 depositId,
        uint256 depositAmount
    ) public returns (uint256) {
        vm.startPrank(user);
        tokenA.approve(address(liquidityManager), depositAmount);
        liquidityManager.deposit(depositId, depositAmount);
        vm.stopPrank();
        return 0;
    }

    function withdraw(
        address user,
        bytes16 depositId
    ) public returns (uint256) {
        vm.startPrank(user);
        liquidityManager.withdraw(depositId);
        vm.stopPrank();
        return 0;
    }

    function test_DepositCreatesDepositRecord() public {
        // Arrange
        uint256 depositAmount = 10 * 1e6; // Adjust decimals as needed
        bytes16 depositId = bytes16(keccak256(abi.encodePacked("testDeposit", block.timestamp)));

        // Act
        deposit(alice, depositId, depositAmount);

        // Assert
        Deposit memory dep = liquidityManager.getUserDeposit(alice, depositId);
        assertEq(dep.id, depositId, "Deposit ID mismatch");
        assertGt(dep.shares, 0, "Shares should be > 0");
        assertGt(dep.amount0Contributed + dep.amount1Contributed, 0, "Amounts should be > 0");
    }

    function test_WithdrawReturnsTokenAAndDepositIsInactive() public {
        // Arrange
        uint256 depositAmount = 10 * 1e6; // Adjust decimals as needed
        bytes16 depositId = bytes16(keccak256(abi.encodePacked("testWithdraw", block.timestamp)));
        deposit(alice, depositId, depositAmount);
        uint256 balanceBefore = tokenA.balanceOf(alice);

        // Act
        withdraw(alice, depositId);

        // Assert
        uint256 balanceAfter = tokenA.balanceOf(alice);
        assertGt(balanceAfter, balanceBefore, "Should receive TokenA back");
        Deposit memory dep = liquidityManager.getUserDeposit(alice, depositId);
        assertEq(dep.isActive, false, "Deposit should be inactive");
        // contract address should have no tokens
        assertEq(tokenA.balanceOf(address(liquidityManager)), 0, "TokenA balance should be 0");
        assertEq(tokenB.balanceOf(address(liquidityManager)), 0, "TokenB balance should be 0");
    }

    function test_TwoDepositsAndWithdraw() public {
        // Arrange
        uint256 depositAmount = 20 * 1e6; // Adjust decimals as needed
        uint256 depositAmount2 = 10 * 1e6;
        bytes16 depositId = bytes16(keccak256(abi.encodePacked("testTwoDepositsAndWithdraw", block.timestamp)));
        bytes16 depositId2 = bytes16(keccak256(abi.encodePacked("testTwoDepositsAndWithdraw2", block.timestamp)));
        deposit(alice, depositId, depositAmount);
        deposit(alice, depositId2, depositAmount2);
        withdraw(alice, depositId);
        // second deposit should already exist in liquidityManager contract
        Deposit memory dep = liquidityManager.getUserDeposit(alice, depositId2);
        assertEq(dep.shares, liquidityManager.totalShares(), "Deposit should be 20");
    }

    function test_CannotDepositWithZeroAmountOrDuplicateId() public {
        uint256 depositAmount = 10 * 1e6;
        bytes16 depositId = bytes16(keccak256(abi.encodePacked("testZeroOrDuplicate", block.timestamp)));

        // Zero amount - call directly, not through TestUtils
        vm.startPrank(alice);
        tokenA.approve(address(liquidityManager), 0);
        vm.expectRevert("Deposit amount must be greater than 0");
        liquidityManager.deposit(depositId, 0);
        vm.stopPrank();

        // Normal deposit
        vm.startPrank(alice);
        tokenA.approve(address(liquidityManager), depositAmount);
        liquidityManager.deposit(depositId, depositAmount);
        vm.stopPrank();

        // Duplicate depositId
        vm.startPrank(alice);
        tokenA.approve(address(liquidityManager), depositAmount);
        vm.expectRevert("Deposit ID already exists for user");
        liquidityManager.deposit(depositId, depositAmount);
        vm.stopPrank();
    }

    function test_CannotWithdrawNonexistentDeposit() public {
        bytes16 depositId = bytes16(keccak256(abi.encodePacked("testNonexistent", block.timestamp)));
        vm.expectRevert("Deposit is not active");
        liquidityManager.withdraw(depositId);
    }

    function test_MultiUserDeposits() public {
        uint256 depositAmount = 10 * 1e6;
        bytes16 aliceDepositId = bytes16(keccak256(abi.encodePacked("aliceDeposit", block.timestamp)));
        bytes16 bobDepositId = bytes16(keccak256(abi.encodePacked("bobDeposit", block.timestamp)));
        bytes16 charlieDepositId = bytes16(keccak256(abi.encodePacked("charlieDeposit", block.timestamp)));
        // Alice deposit
        deposit(alice, aliceDepositId, depositAmount);
        // Bob deposit
        deposit(bob, bobDepositId, depositAmount);
        // Charlie deposit
        deposit(charlie, charlieDepositId, depositAmount);

        // Assert both have deposits
        Deposit memory depAlice = liquidityManager.getUserDeposit(alice, aliceDepositId);
        Deposit memory depBob = liquidityManager.getUserDeposit(bob, bobDepositId);
        Deposit memory depCharlie = liquidityManager.getUserDeposit(charlie, charlieDepositId);
        assertGt(depAlice.shares, 0, "Alice shares should be > 0");
        assertGt(depBob.shares, 0, "Bob shares should be > 0");
        assertGt(depCharlie.shares, 0, "Charlie shares should be > 0");
        uint256 positionTokenId = liquidityManager.positionTokenId();
        (,,,,,,,uint256 liquidity,,,,) = INonfungiblePositionManager(positionManager).positions(positionTokenId);
        assertEq(liquidity, depAlice.shares + depBob.shares + depCharlie.shares, "Liquidity should be equal");
    }

    function test_MultiUserWithdraw() public {
        uint256 aliceDepositAmount = 100_000 * 1e6;
        uint256 bobDepositAmount = 100_000 * 1e6;
        bytes16 aliceDepositId = bytes16(keccak256(abi.encodePacked("aliceDeposit", block.timestamp)));
        console.log("Alice depositId");
        console.logBytes16(aliceDepositId);
        bytes16 bobDepositId = bytes16(keccak256(abi.encodePacked("bobDeposit", block.timestamp)));
        console.log("Bob depositId");
        console.logBytes16(bobDepositId);
        // Alice deposit
        uint256 aliceShares = deposit(alice, aliceDepositId, aliceDepositAmount);
        console.log("Alice shares:", aliceShares);
        // Bob deposit
        uint256 bobShares = deposit(bob, bobDepositId, bobDepositAmount);
        console.log("Bob shares:", bobShares);

        // whale swaps USDC.e to USDT
        generateSwapFees(
            whale,
            tokenA,
            tokenB,
            universalRouter,
            v3SwapExactIn,
            tickSpacing,
            1000_000e6
        );

        // Check tokens owed and liquidity
        uint256 positionTokenId = liquidityManager.positionTokenId();
        uint256 liquidity;
        (,,,,,,,liquidity,,,,) = INonfungiblePositionManager(positionManager).positions(positionTokenId);
        assertGt(liquidity, 0, "Liquidity should be > 0");

        // Alice withdraw
        withdraw(alice, aliceDepositId);

        // Bob withdraw
        withdraw(bob, bobDepositId);
        // Assert both have no deposits
        Deposit memory depAlice = liquidityManager.getUserDeposit(alice, aliceDepositId);
        Deposit memory depBob = liquidityManager.getUserDeposit(bob, bobDepositId);
        assertEq(depAlice.isActive, false, "Alice deposit should be inactive");
        assertEq(depBob.isActive, false, "Bob deposit should be inactive");
        (,,,,,,,liquidity,,,,) = INonfungiblePositionManager(positionManager).positions(positionTokenId);
        assertEq(liquidity, 0, "Liquidity should be 0");
    }

    function test_ComplexMultiUserFlow() public {
        uint256 depositAmountA1 = 10 * 1e6;
        uint256 depositAmountA2 = 15 * 1e6;
        uint256 depositAmountB1 = 20 * 1e6;
        uint256 depositAmountB2 = 25 * 1e6;
        uint256 depositAmountB3 = 30 * 1e6;
        uint256 depositAmountC1 = 12 * 1e6;
        uint256 depositAmountD1 = 14 * 1e6;
        // Unique deposit IDs
        bytes16 aliceDeposit1 = bytes16(keccak256(abi.encodePacked("aliceDeposit1", block.timestamp)));
        bytes16 aliceDeposit2 = bytes16(keccak256(abi.encodePacked("aliceDeposit2", block.timestamp)));
        bytes16 bobDeposit1 = bytes16(keccak256(abi.encodePacked("bobDeposit1", block.timestamp)));
        bytes16 bobDeposit2 = bytes16(keccak256(abi.encodePacked("bobDeposit2", block.timestamp)));
        bytes16 bobDeposit3 = bytes16(keccak256(abi.encodePacked("bobDeposit3", block.timestamp)));
        bytes16 charlieDeposit1 = bytes16(keccak256(abi.encodePacked("charlieDeposit1", block.timestamp)));
        bytes16 daveDeposit1 = bytes16(keccak256(abi.encodePacked("daveDeposit1", block.timestamp)));
        // 1. Alice deposits first
        deposit(alice, aliceDeposit1, depositAmountA1);

        // 2. Alice deposits second
        deposit(alice, aliceDeposit2, depositAmountA2);

        // 3. Bob deposits first
        vm.startPrank(bob);
        tokenA.approve(address(liquidityManager), depositAmountB1);
        deposit(bob, bobDeposit1, depositAmountB1);
        vm.stopPrank();

        // 4. Bob deposits second
        deposit(bob, bobDeposit2, depositAmountB2);

        // 5. Alice withdraws first
        withdraw(alice, aliceDeposit1);
        // Assert Alice deposit1 is inactive
        Deposit memory depA1 = liquidityManager.getUserDeposit(alice, aliceDeposit1);
        assertEq(depA1.isActive, false, "Alice deposit1 should be inactive");

        // 6. Charlie deposits first
        deposit(charlie, charlieDeposit1, depositAmountC1);

        // 7. Bob deposits third
        deposit(bob, bobDeposit3, depositAmountB3);

        // 8. Alice withdraws second
        withdraw(alice, aliceDeposit2);
        // Assert Alice deposit2 is inactive
        Deposit memory depA2 = liquidityManager.getUserDeposit(alice, aliceDeposit2);
        assertEq(depA2.isActive, false, "Alice deposit2 should be inactive");

        // 9. Bob withdraws third
        withdraw(bob, bobDeposit3);
        // Assert Bob deposit3 is inactive
        Deposit memory depB3 = liquidityManager.getUserDeposit(bob, bobDeposit3);
        assertEq(depB3.isActive, false, "Bob deposit3 should be inactive");

        // 10. Bob withdraws second
        withdraw(bob, bobDeposit2);
        // Assert Bob deposit2 is inactive
        Deposit memory depB2 = liquidityManager.getUserDeposit(bob, bobDeposit2);
        assertEq(depB2.isActive, false, "Bob deposit2 should be inactive");

        // 11. Bob withdraws first
        withdraw(bob, bobDeposit1);
        // Assert Bob deposit1 is inactive
        Deposit memory depB1 = liquidityManager.getUserDeposit(bob, bobDeposit1);
        assertEq(depB1.isActive, false, "Bob deposit1 should be inactive");

        // 12. Charlie withdraws first
        withdraw(charlie, charlieDeposit1);
        // Assert Charlie deposit1 is inactive
        Deposit memory depC1 = liquidityManager.getUserDeposit(charlie, charlieDeposit1);
        assertEq(depC1.isActive, false, "Charlie deposit1 should be inactive");

        // 13. Dave deposits first
        deposit(dave, daveDeposit1, depositAmountD1);

        // 14. Dave withdraws first
        withdraw(dave, daveDeposit1);

        Deposit memory depD1 = liquidityManager.getUserDeposit(dave, daveDeposit1);
        assertEq(depD1.isActive, false, "Dave deposit1 should be inactive");

        // 15. Verify nothing is left in the contract
        assertEq(tokenA.balanceOf(address(liquidityManager)), 0, "TokenA balance should be 0");
        assertEq(tokenB.balanceOf(address(liquidityManager)), 0, "TokenB balance should be 0");
    }

    function test_PauseAndUnpause() public {
        // Only owner can pause
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        liquidityManager.pause();

        // Owner can pause
        vm.prank(owner);
        liquidityManager.pause();
        assertTrue(liquidityManager.paused(), "Contract should be paused");

        // Deposit should revert when paused
        vm.prank(alice);
        vm.expectRevert();
        liquidityManager.deposit(bytes16(keccak256("id1")), 1e6);

        // Withdraw should revert when paused
        vm.prank(alice);
        vm.expectRevert();
        liquidityManager.withdraw(bytes16(keccak256("id1")));

        // Only owner can unpause
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        liquidityManager.unpause();

        // Owner can unpause
        vm.prank(owner);
        liquidityManager.unpause();
        assertFalse(liquidityManager.paused(), "Contract should be unpaused");
    }

    function test_GetUserDepositIds() public {
        // Arrange
        uint256 depositAmount1 = 10 * 1e6;
        uint256 depositAmount2 = 20 * 1e6;
        bytes16 depositId1 = bytes16(keccak256(abi.encodePacked("getUserDepositIds1", block.timestamp, "a")));
        bytes16 depositId2 = bytes16(keccak256(abi.encodePacked("getUserDepositIds2", block.timestamp, "b")));

        // Act
        deposit(alice, depositId1, depositAmount1);
        deposit(alice, depositId2, depositAmount2);

        // Assert
        bytes16[] memory ids = liquidityManager.getUserDepositIds(alice);
        assertEq(ids.length, 2, "Should have 2 deposit IDs");
        assertEq(ids[0], depositId1, "First depositId mismatch");
        assertEq(ids[1], depositId2, "Second depositId mismatch");

        // Withdraw one and check IDs remain (withdraw does not remove from getUserDepositIds)
        withdraw(alice, depositId1);
        bytes16[] memory idsAfterWithdraw = liquidityManager.getUserDepositIds(alice);
        assertEq(idsAfterWithdraw.length, 2, "IDs array length should remain after withdraw");
        assertEq(idsAfterWithdraw[0], depositId1, "First depositId mismatch after withdraw");
        assertEq(idsAfterWithdraw[1], depositId2, "Second depositId mismatch after withdraw");
    }
}