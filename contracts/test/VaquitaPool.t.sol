// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {VaquitaPool} from "../src/VaquitaPool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IUniversalRouter} from "../src/interfaces/external/IUniversalRouter.sol";
import {MintParams} from "../src/interfaces/external/INonFungiblePositionManager.sol";

// Mock ERC20 Token
contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
        decimals = 18;
    }

    function mint(address to, uint256 amount) public {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function transfer(address to, uint256 amount) public returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;
        return true;
    }

    function approve(address spender, uint256 amount) public returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}

// Mock Universal Router
contract MockUniversalRouter is IUniversalRouter {
    function execute(bytes calldata commands, bytes[] calldata inputs, uint256 deadline) external payable {
        // Mock implementation - just accept the call
        require(block.timestamp <= deadline, "TransactionDeadlinePassed");
    }

    function execute(bytes calldata commands, bytes[] calldata inputs) external payable {
        // Mock implementation - just accept the call
    }

    function collectRewards(bytes calldata looksRareClaim) external {
        // Mock implementation
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external pure returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4) external pure returns (bool) {
        return true;
    }
}

contract MockNonFungiblePositionManager {
    function mint(MintParams calldata params) external {
        // Mock implementation
    }
}

contract VaquitaTest is Test {
    VaquitaPool public vaquita;
    MockERC20 public tokenA;
    MockERC20 public tokenB;
    MockUniversalRouter public router;
    MockNonFungiblePositionManager public nft;

    function setUp() public {
        // Deploy mock tokens
        tokenA = new MockERC20("Token A", "TKA");
        tokenB = new MockERC20("Token B", "TKB");
        
        // Deploy mock router
        router = new MockUniversalRouter();
        nft = new MockNonFungiblePositionManager();
        
        // Deploy VaquitaPool with mock addresses
        vaquita = new VaquitaPool(
            address(tokenA),
            address(tokenB),
            address(router),
            address(0x991d5546C4B442B4c5fdc4c8B8b8d131DEB24702),
            0x00,
            1
        );
    }
}
