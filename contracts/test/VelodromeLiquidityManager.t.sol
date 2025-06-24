// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {VelodromeLiquidityManager, Deposit} from "../src/VelodromeLiquidityManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract VelodromeLiquidityManagerTest is Test {
    VelodromeLiquidityManager public liquidityManager;
    IERC20 public tokenA;
    IERC20 public tokenB;
    address public universalRouter;
    address public positionManager;
    address public whale;

    address public alice;
    address public bob;
    address public carol;
    address public dave;

    // Real Lisk mainnet addresses from VelodromeLiquidityManager.s.sol
    address constant TOKEN_A_ADDRESS = 0xF242275d3a6527d877f2c927a82D9b057609cc71;
    address constant TOKEN_B_ADDRESS = 0x05D032ac25d322df992303dCa074EE7392C117b9;
    address constant UNIVERSAL_ROUTER_ADDRESS = 0x652e53C6a4FE39B6B30426d9c96376a105C89A95;
    address constant POSITION_MANAGER_ADDRESS = 0x991d5546C4B442B4c5fdc4c8B8b8d131DEB24702;
    address constant TOKEN_A_WHALE = 0xC859c755E8C0568fD86F7860Bcf9A59D6F57BEB5;

    uint256 public v3SwapExactIn = 0x00;
    int24 public tickSpacing = 1;
    int24 public tickLower = 3;
    int24 public tickUpper = 6;

    function setUp() public {
        // Best practice: fork Lisk mainnet here for reproducibility and CI
        // This ensures the fork is always set, regardless of test command arguments
        uint256 lisk_fork_block = 17_998_944;
        vm.createSelectFork(vm.rpcUrl("lisk"), lisk_fork_block);
        console.log("address(this)", address(this));

        // Assign real contract addresses
        tokenA = IERC20(TOKEN_A_ADDRESS);
        tokenB = IERC20(TOKEN_B_ADDRESS);
        universalRouter = UNIVERSAL_ROUTER_ADDRESS;
        positionManager = POSITION_MANAGER_ADDRESS;
        whale = TOKEN_A_WHALE;

        // Create test users
        alice = address(0xA11CE);
        bob = address(0xB0B);
        carol = makeAddr("carol");
        dave = makeAddr("dave");
        // Impersonate whale and transfer TokenA to alice and bob
        uint256 transferAmount = 1_000 * 1e6; // Adjust decimals as needed
        vm.startPrank(whale);
        tokenA.transfer(alice, transferAmount);
        tokenA.transfer(bob, transferAmount);
        tokenA.transfer(carol, transferAmount);
        tokenA.transfer(dave, transferAmount);
        vm.stopPrank();

        // Deploy VelodromeLiquidityManager with real addresses and parameters
        liquidityManager = new VelodromeLiquidityManager(
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

    function testDepositCreatesDepositRecord() public {
        // Arrange
        uint256 depositAmount = 10 * 1e6; // Adjust decimals as needed
        vm.startPrank(alice);
        tokenA.approve(address(liquidityManager), depositAmount);
        bytes16 depositId = bytes16(keccak256(abi.encodePacked("testDeposit", block.timestamp)));

        // Act
        liquidityManager.deposit(depositId, depositAmount);

        // Assert
        Deposit memory dep = liquidityManager.getUserDeposit(alice, depositId);
        assertEq(dep.id, depositId, "Deposit ID mismatch");
        assertGt(dep.shares, 0, "Shares should be > 0");
        assertGt(dep.amount0Contributed + dep.amount1Contributed, 0, "Amounts should be > 0");
        vm.stopPrank();
    }

    function testWithdrawReturnsTokenAAndDeletesDeposit() public {
        // Arrange
        uint256 depositAmount = 10 * 1e6; // Adjust decimals as needed
        vm.startPrank(alice);
        tokenA.approve(address(liquidityManager), depositAmount);
        bytes16 depositId = bytes16(keccak256(abi.encodePacked("testWithdraw", block.timestamp)));
        liquidityManager.deposit(depositId, depositAmount);
        uint256 balanceBefore = tokenA.balanceOf(alice);
        console.log("t_balanceBefore", balanceBefore);
        console.log("t_tokenA balance of contract", tokenA.balanceOf(address(liquidityManager)));

        // Act
        liquidityManager.withdraw(depositId);

        // Assert
        uint256 balanceAfter = tokenA.balanceOf(alice);
        console.log("t_balanceAfter", balanceAfter);
        assertGt(balanceAfter, balanceBefore, "Should receive TokenA back");
        Deposit memory dep = liquidityManager.getUserDeposit(alice, depositId);
        assertEq(dep.shares, 0, "Deposit should be deleted");
        // contract address should have no tokens
        console.log("t_tokenB balance of contract", tokenB.balanceOf(address(liquidityManager)));
        assertEq(tokenA.balanceOf(address(liquidityManager)), 0, "TokenA balance should be 0");
        assertEq(tokenB.balanceOf(address(liquidityManager)), 0, "TokenB balance should be 0");
        vm.stopPrank();
    }

    function testTwoDepositsAndWithdraw() public {
        // Arrange
        uint256 depositAmount = 20 * 1e6; // Adjust decimals as needed
        uint256 depositAmount2 = 10 * 1e6;
        bytes16 depositId = bytes16(keccak256(abi.encodePacked("testTwoDepositsAndWithdraw", block.timestamp)));
        bytes16 depositId2 = bytes16(keccak256(abi.encodePacked("testTwoDepositsAndWithdraw2", block.timestamp)));
        vm.startPrank(alice);
        tokenA.approve(address(liquidityManager), depositAmount + depositAmount2);
        liquidityManager.deposit(depositId, depositAmount);
        liquidityManager.deposit(depositId2, depositAmount2);
        liquidityManager.withdraw(depositId);
        // second deposit should already exist in liquidityManager contract
        Deposit memory dep = liquidityManager.getUserDeposit(alice, depositId2);
        assertEq(dep.shares, liquidityManager.totalShares(), "Deposit should be 20");
        vm.stopPrank();
    }

    function testCannotDepositWithZeroAmountOrDuplicateId() public {
        uint256 depositAmount = 10 * 1e6; // Adjust decimals as needed
        vm.startPrank(alice);
        tokenA.approve(address(liquidityManager), depositAmount);
        bytes16 depositId = bytes16(keccak256(abi.encodePacked("testZeroOrDuplicate", block.timestamp)));

        // Zero amount
        vm.expectRevert("Deposit amount must be greater than 0");
        liquidityManager.deposit(depositId, 0);

        // Normal deposit
        liquidityManager.deposit(depositId, depositAmount);

        // Duplicate depositId
        vm.expectRevert("Deposit ID already exists for user");
        liquidityManager.deposit(depositId, depositAmount);
        vm.stopPrank();
    }

    function testCannotWithdrawNonexistentDeposit() public {
        bytes16 depositId = bytes16(keccak256(abi.encodePacked("testNonexistent", block.timestamp)));
        vm.expectRevert("Deposit not found or already withdrawn for user");
        liquidityManager.withdraw(depositId);
    }

    function testMultiUserDeposits() public {
        uint256 depositAmount = 10 * 1e6;
        bytes16 aliceDepositId = bytes16(keccak256(abi.encodePacked("aliceDeposit", block.timestamp)));
        bytes16 bobDepositId = bytes16(keccak256(abi.encodePacked("bobDeposit", block.timestamp)));
        // Alice deposit
        vm.startPrank(alice);
        tokenA.approve(address(liquidityManager), depositAmount);
        liquidityManager.deposit(aliceDepositId, depositAmount);
        vm.stopPrank();
        // Bob deposit
        vm.startPrank(bob);
        tokenA.approve(address(liquidityManager), depositAmount);
        liquidityManager.deposit(bobDepositId, depositAmount);
        vm.stopPrank();
        // Assert both have deposits
        Deposit memory depAlice = liquidityManager.getUserDeposit(alice, aliceDepositId);
        Deposit memory depBob = liquidityManager.getUserDeposit(bob, bobDepositId);
        assertGt(depAlice.shares, 0, "Alice shares should be > 0");
        assertGt(depBob.shares, 0, "Bob shares should be > 0");
    }

    function testMultiUserWithdraw() public {
        uint256 aliceDepositAmount = 10 * 1e6;
        uint256 bobDepositAmount = 20 * 1e6;
        bytes16 aliceDepositId = bytes16(keccak256(abi.encodePacked("aliceDeposit", block.timestamp)));
        bytes16 bobDepositId = bytes16(keccak256(abi.encodePacked("bobDeposit", block.timestamp)));
        uint256 aliceBalanceBefore = tokenA.balanceOf(alice);
        uint256 bobBalanceBefore = tokenA.balanceOf(bob);
        console.log("aliceInitialBalance", aliceBalanceBefore);
        console.log("bobInitialBalance", bobBalanceBefore);
        // Alice deposit
        vm.startPrank(alice);
        tokenA.approve(address(liquidityManager), aliceDepositAmount);
        liquidityManager.deposit(aliceDepositId, aliceDepositAmount);
        vm.stopPrank();
        // Bob deposit
        vm.startPrank(bob);
        tokenA.approve(address(liquidityManager), bobDepositAmount);
        liquidityManager.deposit(bobDepositId, bobDepositAmount);
        vm.stopPrank();
        // Alice withdraw
        vm.startPrank(alice);
        liquidityManager.withdraw(aliceDepositId);
        vm.stopPrank();
        // Bob withdraw
        vm.startPrank(bob);
        liquidityManager.withdraw(bobDepositId);
        vm.stopPrank();
        // Assert both have no deposits
        Deposit memory depAlice = liquidityManager.getUserDeposit(alice, aliceDepositId);
        Deposit memory depBob = liquidityManager.getUserDeposit(bob, bobDepositId);
        console.log("aliceFinalBalance", tokenA.balanceOf(alice));
        console.log("bobFinalBalance", tokenA.balanceOf(bob));
        assertEq(depAlice.shares, 0, "Alice shares should be 0");
        assertEq(depBob.shares, 0, "Bob shares should be 0");
    }

    function testComplexMultiUserFlow() public {
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
        bytes16 carolDeposit1 = bytes16(keccak256(abi.encodePacked("carolDeposit1", block.timestamp)));
        bytes16 daveDeposit1 = bytes16(keccak256(abi.encodePacked("daveDeposit1", block.timestamp)));
        // 1. Alice deposits first
        vm.startPrank(alice);
        tokenA.approve(address(liquidityManager), depositAmountA1);
        liquidityManager.deposit(aliceDeposit1, depositAmountA1);
        vm.stopPrank();

        // 2. Alice deposits second
        vm.startPrank(alice);
        tokenA.approve(address(liquidityManager), depositAmountA2);
        liquidityManager.deposit(aliceDeposit2, depositAmountA2);
        vm.stopPrank();

        // 3. Bob deposits first
        vm.startPrank(bob);
        tokenA.approve(address(liquidityManager), depositAmountB1);
        liquidityManager.deposit(bobDeposit1, depositAmountB1);
        vm.stopPrank();

        // 4. Bob deposits second
        vm.startPrank(bob);
        tokenA.approve(address(liquidityManager), depositAmountB2);
        liquidityManager.deposit(bobDeposit2, depositAmountB2);
        vm.stopPrank();

        // 5. Alice withdraws first
        vm.startPrank(alice);
        liquidityManager.withdraw(aliceDeposit1);
        vm.stopPrank();
        Deposit memory depA1 = liquidityManager.getUserDeposit(alice, aliceDeposit1);
        assertEq(depA1.shares, 0, "Alice deposit1 should be deleted");

        // 6. Carol deposits first
        vm.startPrank(carol);
        tokenA.approve(address(liquidityManager), depositAmountC1);
        liquidityManager.deposit(carolDeposit1, depositAmountC1);
        vm.stopPrank();

        // 7. Bob deposits third
        vm.startPrank(bob);
        tokenA.approve(address(liquidityManager), depositAmountB3);
        liquidityManager.deposit(bobDeposit3, depositAmountB3);
        vm.stopPrank();

        // 8. Alice withdraws second
        vm.startPrank(alice);
        liquidityManager.withdraw(aliceDeposit2);
        vm.stopPrank();
        Deposit memory depA2 = liquidityManager.getUserDeposit(alice, aliceDeposit2);
        assertEq(depA2.shares, 0, "Alice deposit2 should be deleted");

        // 9. Bob withdraws third
        vm.startPrank(bob);
        liquidityManager.withdraw(bobDeposit3);
        vm.stopPrank();
        Deposit memory depB3 = liquidityManager.getUserDeposit(bob, bobDeposit3);
        assertEq(depB3.shares, 0, "Bob deposit3 should be deleted");

        // 10. Bob withdraws second
        vm.startPrank(bob);
        liquidityManager.withdraw(bobDeposit2);
        vm.stopPrank();
        Deposit memory depB2 = liquidityManager.getUserDeposit(bob, bobDeposit2);
        assertEq(depB2.shares, 0, "Bob deposit2 should be deleted");

        // 11. Bob withdraws first
        vm.startPrank(bob);
        liquidityManager.withdraw(bobDeposit1);
        vm.stopPrank();
        Deposit memory depB1 = liquidityManager.getUserDeposit(bob, bobDeposit1);
        assertEq(depB1.shares, 0, "Bob deposit1 should be deleted");

        // 12. Carol withdraws first
        vm.startPrank(carol);
        liquidityManager.withdraw(carolDeposit1);
        vm.stopPrank();
        Deposit memory depC1 = liquidityManager.getUserDeposit(carol, carolDeposit1);
        assertEq(depC1.shares, 0, "Carol deposit1 should be deleted");

        // 13. Dave deposits first
        vm.startPrank(dave);
        tokenA.approve(address(liquidityManager), depositAmountD1);
        liquidityManager.deposit(daveDeposit1, depositAmountD1);
        vm.stopPrank();

        // 14. Dave withdraws first
        vm.startPrank(dave);
        liquidityManager.withdraw(daveDeposit1);
        vm.stopPrank();
        Deposit memory depD1 = liquidityManager.getUserDeposit(dave, daveDeposit1);
        assertEq(depD1.shares, 0, "Dave deposit1 should be deleted");

        // 15. Verify nothing is left in the contract
        assertEq(tokenA.balanceOf(address(liquidityManager)), 0, "TokenA balance should be 0");
        assertEq(tokenB.balanceOf(address(liquidityManager)), 0, "TokenB balance should be 0");

        // Print final balances
        console.log("aliceFinalBalance", tokenA.balanceOf(alice));
        console.log("bobFinalBalance", tokenA.balanceOf(bob));
        console.log("carolFinalBalance", tokenA.balanceOf(carol));
        console.log("daveFinalBalance", tokenA.balanceOf(dave));
    }
}