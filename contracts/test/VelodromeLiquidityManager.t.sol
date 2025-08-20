// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {VelodromeLiquidityManager} from "../src/VelodromeLiquidityManager.sol";
import {INonfungiblePositionManager} from "../src/interfaces/external/INonFungiblePositionManager.sol";
import {IUniversalRouter} from "../src/interfaces/external/IUniversalRouter.sol";
import {TestUtils} from "./TestUtils.sol";
import {IVelodromeLiquidityManager} from "../src/interfaces/IVelodromeLiquidityManager.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract VelodromeLiquidityManagerTest is TestUtils {
    VelodromeLiquidityManager public liquidityManager;
    IERC20 public token0;
    IERC20 public token1;
    address public universalRouter;
    address public positionManager;
    address public whale;
    address public owner;

    address public alice;
    address public bob;
    address public charlie;
    address public dave;

    address constant TOKEN_0_ADDRESS = 0x05D032ac25d322df992303dCa074EE7392C117b9;
    address constant TOKEN_1_ADDRESS = 0xF242275d3a6527d877f2c927a82D9b057609cc71;
    address constant UNIVERSAL_ROUTER_ADDRESS = 0x652e53C6a4FE39B6B30426d9c96376a105C89A95;
    address constant POSITION_MANAGER_ADDRESS = 0x991d5546C4B442B4c5fdc4c8B8b8d131DEB24702;
    address constant TOKEN_1_WHALE = 0xC859c755E8C0568fD86F7860Bcf9A59D6F57BEB5;

    int24 public tickSpacing = 1;
    int24 public tickLower = 3;
    int24 public tickUpper = 6;

    function setUp() public {
        // Best practice: fork Lisk mainnet here for reproducibility and CI
        // This ensures the fork is always set, regardless of test command arguments
        uint256 liskForkBlock = 17_998_944;
        vm.createSelectFork(vm.rpcUrl("lisk"), liskForkBlock);

        // Assign real contract addresses
        token0 = IERC20(TOKEN_0_ADDRESS);
        token1 = IERC20(TOKEN_1_ADDRESS);
        universalRouter = UNIVERSAL_ROUTER_ADDRESS;
        positionManager = POSITION_MANAGER_ADDRESS;
        whale = TOKEN_1_WHALE;
        owner = address(this);

        // Create test users
        alice = address(0xA11CE);
        bob = address(0xB0B);
        charlie = makeAddr("charlie");
        dave = makeAddr("dave");
        // Impersonate whale and transfer token1 to alice and bob
        uint256 transferAmount = 100_000 * 1e6; // Adjust decimals as needed
        uint256 transferAmount2 = 1_000 * 1e6;
        vm.startPrank(whale);
        token1.transfer(alice, transferAmount);
        token1.transfer(bob, transferAmount);
        token1.transfer(charlie, transferAmount2);
        token1.transfer(dave, transferAmount2);
        vm.stopPrank();

        // Deploy liquidity manager implementation and proxy
        VelodromeLiquidityManager liquidityManagerImpl = new VelodromeLiquidityManager();
        bytes memory liquidityManagerInitData = abi.encodeWithSelector(
            liquidityManagerImpl.initialize.selector,
            address(token0),
            address(token1),
            address(universalRouter),
            address(positionManager),
            tickSpacing,
            tickLower,
            tickUpper,
            false
        );
        TransparentUpgradeableProxy liquidityManagerProxy = new TransparentUpgradeableProxy(
            address(liquidityManagerImpl),
            owner,
            liquidityManagerInitData
        );
        liquidityManager = VelodromeLiquidityManager(address(liquidityManagerProxy));
    }

    function deposit(
        address user,
        bytes32 depositId,
        uint256 depositAmount
    ) public returns (uint256) {
        vm.startPrank(user);
        token1.approve(address(liquidityManager), depositAmount);
        liquidityManager.deposit(depositId, address(token1), depositAmount, 0, 0, 0, block.timestamp);
        vm.stopPrank();
        return 0;
    }

    function withdraw(
        address user,
        bytes32 depositId
    ) public returns (uint256) {
        vm.startPrank(user);
        liquidityManager.withdraw(depositId, address(token1), 0, 0, 0, block.timestamp);
        vm.stopPrank();
        return 0;
    }

    function test_DepositCreatesDepositRecord() public {
        // Arrange
        uint256 depositAmount = 10 * 1e6; // Adjust decimals as needed
        bytes32 depositId = bytes32(keccak256(abi.encodePacked("testDeposit", block.timestamp)));

        // Act
        deposit(alice, depositId, depositAmount);

        // Assert
        (uint256 shares,,,bool isActive) = liquidityManager.userDepositDetails(alice, depositId);
        assertGt(shares, 0, "Shares should be > 0");
        assertEq(isActive, true, "Deposit should be active");
    }

    function test_WithdrawReturnsToken1AndDepositIsInactive() public {
        // Arrange
        uint256 depositAmount = 10 * 1e6; // Adjust decimals as needed
        bytes32 depositId = bytes32(keccak256(abi.encodePacked("testWithdraw", block.timestamp)));
        deposit(alice, depositId, depositAmount);
        uint256 balanceBefore = token1.balanceOf(alice);

        // Act
        withdraw(alice, depositId);

        // Assert
        uint256 balanceAfter = token1.balanceOf(alice);
        assertGt(balanceAfter, balanceBefore, "Should receive token1 back");
        (,,, bool isActive) = liquidityManager.userDepositDetails(alice, depositId);
        assertEq(isActive, false, "Deposit should be inactive");
        // contract address should have no tokens
        assertEq(token0.balanceOf(address(liquidityManager)), 0, "token0 balance should be 0");
        assertEq(token1.balanceOf(address(liquidityManager)), 0, "token1 balance should be 0");
    }

    function test_TwoDepositsAndWithdraw() public {
        // Arrange
        uint256 depositAmount = 20 * 1e6; // Adjust decimals as needed
        uint256 depositAmount2 = 10 * 1e6;
        bytes32 depositId = bytes32(keccak256(abi.encodePacked("testTwoDepositsAndWithdraw", block.timestamp)));
        bytes32 depositId2 = bytes32(keccak256(abi.encodePacked("testTwoDepositsAndWithdraw2", block.timestamp)));
        deposit(alice, depositId, depositAmount);
        deposit(alice, depositId2, depositAmount2);
        withdraw(alice, depositId);
        // second deposit should already exist in liquidityManager contract
        (uint256 shares,,,) = liquidityManager.userDepositDetails(alice, depositId2);
        assertEq(shares, liquidityManager.totalShares(), "Deposit should be 20");
    }

    function test_CannotDepositWithZeroAmountOrDuplicateId() public {
        uint256 depositAmount = 10 * 1e6;
        bytes32 depositId = bytes32(keccak256(abi.encodePacked("testZeroOrDuplicate", block.timestamp)));

        // Zero amount - call directly, not through TestUtils
        vm.startPrank(alice);
        token1.approve(address(liquidityManager), 0);
        vm.expectRevert("Deposit amountA must be greater than 0");
        liquidityManager.deposit(depositId, address(token1), 0, 0, 0, 0, block.timestamp);
        vm.stopPrank();

        // Normal deposit
        vm.startPrank(alice);
        token1.approve(address(liquidityManager), depositAmount);
        liquidityManager.deposit(depositId, address(token1), depositAmount, 0, 0, 0, block.timestamp);
        vm.stopPrank();

        // Duplicate depositId
        vm.startPrank(alice);
        token1.approve(address(liquidityManager), depositAmount);
        vm.expectRevert("Deposit ID already exists for user");
        liquidityManager.deposit(depositId, address(token1), depositAmount, 0, 0, 0, block.timestamp);
        vm.stopPrank();
    }

    function test_CannotWithdrawNonexistentDeposit() public {
        bytes32 depositId = bytes32(keccak256(abi.encodePacked("testNonexistent", block.timestamp)));
        vm.expectRevert("Deposit is not active");
        withdraw(alice, depositId);
    }

    function test_MultiUserDeposits() public {
        uint256 depositAmount = 10 * 1e6;
        bytes32 aliceDepositId = bytes32(keccak256(abi.encodePacked("aliceDeposit", block.timestamp)));
        bytes32 bobDepositId = bytes32(keccak256(abi.encodePacked("bobDeposit", block.timestamp)));
        bytes32 charlieDepositId = bytes32(keccak256(abi.encodePacked("charlieDeposit", block.timestamp)));
        // Alice deposit
        deposit(alice, aliceDepositId, depositAmount);
        // Bob deposit
        deposit(bob, bobDepositId, depositAmount);
        // Charlie deposit
        deposit(charlie, charlieDepositId, depositAmount);

        // Assert both have deposits
        (uint256 sharesAlice,,,) = liquidityManager.userDepositDetails(alice, aliceDepositId);
        (uint256 sharesBob,,,) = liquidityManager.userDepositDetails(bob, bobDepositId);
        (uint256 sharesCharlie,,,) = liquidityManager.userDepositDetails(charlie, charlieDepositId);
        assertGt(sharesAlice, 0, "Alice shares should be > 0");
        assertGt(sharesBob, 0, "Bob shares should be > 0");
        assertGt(sharesCharlie, 0, "Charlie shares should be > 0");
        uint256 positionTokenId = liquidityManager.positionTokenId();
        (,,,,,,,uint256 liquidity,,,,) = INonfungiblePositionManager(positionManager).positions(positionTokenId);
        assertEq(liquidity, sharesAlice + sharesBob + sharesCharlie, "Liquidity should be equal");
    }

    function test_MultiUserWithdraw() public {
        uint256 aliceDepositAmount = 100_000 * 1e6;
        uint256 bobDepositAmount = 100_000 * 1e6;
        bytes32 aliceDepositId = bytes32(keccak256(abi.encodePacked("aliceDeposit", block.timestamp)));
        console.log("Alice depositId");
        console.logBytes32(aliceDepositId);
        bytes32 bobDepositId = bytes32(keccak256(abi.encodePacked("bobDeposit", block.timestamp)));
        console.log("Bob depositId");
        console.logBytes32(bobDepositId);
        // Alice deposit
        uint256 aliceShares = deposit(alice, aliceDepositId, aliceDepositAmount);
        console.log("Alice shares:", aliceShares);
        // Bob deposit
        uint256 bobShares = deposit(bob, bobDepositId, bobDepositAmount);
        console.log("Bob shares:", bobShares);

        // whale swaps USDC.e to USDT
        generateSwapFees(
            whale,
            token1,
            token0,
            universalRouter,
            0x0,
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
        (,,, bool isActiveAlice) = liquidityManager.userDepositDetails(alice, aliceDepositId);
        (,,, bool isActiveBob) = liquidityManager.userDepositDetails(bob, bobDepositId);
        assertEq(isActiveAlice, false, "Alice deposit should be inactive");
        assertEq(isActiveBob, false, "Bob deposit should be inactive");
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
        bytes32 aliceDeposit1 = bytes32(keccak256(abi.encodePacked("aliceDeposit1", block.timestamp)));
        bytes32 aliceDeposit2 = bytes32(keccak256(abi.encodePacked("aliceDeposit2", block.timestamp)));
        bytes32 bobDeposit1 = bytes32(keccak256(abi.encodePacked("bobDeposit1", block.timestamp)));
        bytes32 bobDeposit2 = bytes32(keccak256(abi.encodePacked("bobDeposit2", block.timestamp)));
        bytes32 bobDeposit3 = bytes32(keccak256(abi.encodePacked("bobDeposit3", block.timestamp)));
        bytes32 charlieDeposit1 = bytes32(keccak256(abi.encodePacked("charlieDeposit1", block.timestamp)));
        bytes32 daveDeposit1 = bytes32(keccak256(abi.encodePacked("daveDeposit1", block.timestamp)));
        // 1. Alice deposits first
        deposit(alice, aliceDeposit1, depositAmountA1);

        // 2. Alice deposits second
        deposit(alice, aliceDeposit2, depositAmountA2);

        // 3. Bob deposits first
        vm.startPrank(bob);
        token1.approve(address(liquidityManager), depositAmountB1);
        deposit(bob, bobDeposit1, depositAmountB1);
        vm.stopPrank();

        // 4. Bob deposits second
        deposit(bob, bobDeposit2, depositAmountB2);

        // 5. Alice withdraws first
        withdraw(alice, aliceDeposit1);
        // Assert Alice deposit1 is inactive
        (,,, bool isActiveA1) = liquidityManager.userDepositDetails(alice, aliceDeposit1);
        assertEq(isActiveA1, false, "Alice deposit1 should be inactive");

        // 6. Charlie deposits first
        deposit(charlie, charlieDeposit1, depositAmountC1);

        // 7. Bob deposits third
        deposit(bob, bobDeposit3, depositAmountB3);

        // 8. Alice withdraws second
        withdraw(alice, aliceDeposit2);
        // Assert Alice deposit2 is inactive
        (,,, bool isActiveA2) = liquidityManager.userDepositDetails(alice, aliceDeposit2);
        assertEq(isActiveA2, false, "Alice deposit2 should be inactive");

        // 9. Bob withdraws third
        withdraw(bob, bobDeposit3);
        // Assert Bob deposit3 is inactive
        (,,, bool isActiveB3) = liquidityManager.userDepositDetails(bob, bobDeposit3);
        assertEq(isActiveB3, false, "Bob deposit3 should be inactive");

        // 10. Bob withdraws second
        withdraw(bob, bobDeposit2);
        // Assert Bob deposit2 is inactive
        (,,, bool isActiveB2) = liquidityManager.userDepositDetails(bob, bobDeposit2);
        assertEq(isActiveB2, false, "Bob deposit2 should be inactive");

        // 11. Bob withdraws first
        withdraw(bob, bobDeposit1);
        // Assert Bob deposit1 is inactive
        (,,, bool isActiveB1) = liquidityManager.userDepositDetails(bob, bobDeposit1);
        assertEq(isActiveB1, false, "Bob deposit1 should be inactive");

        // 12. Charlie withdraws first
        withdraw(charlie, charlieDeposit1);
        // Assert Charlie deposit1 is inactive
        (,,, bool isActiveC1) = liquidityManager.userDepositDetails(charlie, charlieDeposit1);
        assertEq(isActiveC1, false, "Charlie deposit1 should be inactive");

        // 13. Dave deposits first
        deposit(dave, daveDeposit1, depositAmountD1);

        // 14. Dave withdraws first
        withdraw(dave, daveDeposit1);

        (,,, bool isActiveD1) = liquidityManager.userDepositDetails(dave, daveDeposit1);
        assertEq(isActiveD1, false, "Dave deposit1 should be inactive");

        // 15. Verify nothing is left in the contract
        assertEq(token0.balanceOf(address(liquidityManager)), 0, "token0 balance should be 0");
        assertEq(token1.balanceOf(address(liquidityManager)), 0, "token1 balance should be 0");
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
        liquidityManager.deposit(bytes32(keccak256("id1")), address(token1), 1e6, 0, 0, 0, block.timestamp);

        // Withdraw should revert when paused
        vm.prank(alice);
        vm.expectRevert();
        liquidityManager.withdraw(bytes32(keccak256("id1")), address(token1), 0, 0, 0, block.timestamp);

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
        bytes32 depositId1 = bytes32(keccak256(abi.encodePacked("getUserDepositIds1", block.timestamp, "a")));
        bytes32 depositId2 = bytes32(keccak256(abi.encodePacked("getUserDepositIds2", block.timestamp, "b")));
        bytes32[] memory depositIds = new bytes32[](2);
        depositIds[0] = depositId1;
        depositIds[1] = depositId2;

        // Act
        vm.startPrank(alice);
        token1.approve(address(liquidityManager), depositAmount1 + depositAmount2);
        vm.expectEmit(true, true, false, false);
        emit IVelodromeLiquidityManager.FundsDeposited(alice, depositId1, 0, 0, 0);
        liquidityManager.deposit(depositId1, address(token1), depositAmount1, 0, 0, 0, block.timestamp);

        vm.expectEmit(true, true, false, false);
        emit IVelodromeLiquidityManager.FundsDeposited(alice, depositId2, 0, 0, 0);
        liquidityManager.deposit(depositId2, address(token1), depositAmount2, 0, 0, 0, block.timestamp);
        vm.stopPrank();
    }
}
