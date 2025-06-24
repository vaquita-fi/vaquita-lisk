# Vaquita Lisk

# VelodromeLiquidityManager

VelodromeLiquidityManager is a robust, modular smart contract system for managing user deposits and liquidity provisioning in Uniswap V3/Velodrome-style concentrated liquidity pools. It enables users to deposit a single token, automatically swaps and adds liquidity, tracks each deposit with a unique UUID, and allows precise, share-based withdrawals with optional token swaps on exit.

This project is designed for advanced DeFi protocols and power users who want to abstract away the complexity of managing Uniswap V3/Velodrome positions, while maintaining transparency, modularity, and extensibility.

## Key Features

- **Single-Token Deposit**: Users deposit tokenA, half is swapped for tokenB, and both are added as liquidity to a Uniswap V3/Velodrome position.
- **Share-Based Accounting**: Each deposit is tracked with shares, allowing precise proportional withdrawals.
- **UUID Tracking**: Every deposit is associated with a unique `bytes16` ID for easy lookup and management.
- **Modular Withdrawals**: On withdrawal, liquidity is removed, tokens are collected, and tokenB can be swapped back to tokenA before returning to the user.
- **Multi-User Support**: Each user can have multiple deposits, tracked independently.
- **Gas-Efficient Approvals**: Uses the approve-once pattern for router and position manager.
- **Events**: Emits `DepositMade` and `Withdrawn` events for off-chain tracking and analytics.
- **Extensive Testing**: Includes Foundry-based Solidity tests and JavaScript integration tests for real-world scenarios.

## Contract Structure

- `contracts/src/VelodromeLiquidityManager.sol`: Main contract implementing all core logic.
- `contracts/src/interfaces/external/IUniversalRouter.sol`: Minimal interface for the Universal Router (swaps).
- `contracts/src/interfaces/external/INonFungiblePositionManager.sol`: Minimal interface for Uniswap V3/Velodrome position manager.
- `contracts/test/VelodromeLiquidityManager.t.sol`: Comprehensive Foundry test suite (multi-user, edge cases, etc).
- `contracts/integration-tests/VelodromeLiquidityManager.test.js`: JS integration tests using ethers.js and Tenderly simulation.

## How It Works

### Deployment
Deploy `VelodromeLiquidityManager` with the addresses of tokenA, tokenB, Universal Router, and Position Manager, plus pool parameters (tick spacing, tick range, etc).

### Deposit
- User calls `deposit(bytes16 depositId, uint256 amount)` with a unique ID and amount of tokenA.
- Contract swaps half of tokenA for tokenB, then adds both as liquidity.
- Shares are minted and tracked per user/deposit.
- Emits `DepositMade` event.

### Withdraw
- User calls `withdraw(bytes16 depositId)`.
- Contract removes proportional liquidity, collects tokens, and (optionally) swaps tokenB back to tokenA.
- User receives their share of tokenA.
- Deposit record is deleted, and `Withdrawn` event is emitted.

### Share Tracking
- Each deposit is tracked by UUID and user address.
- Users can query their deposits and shares at any time.

## Testing

### Solidity (Foundry)
- Located in `contracts/test/VelodromeLiquidityManager.t.sol`.
- Covers single and multi-user scenarios, edge cases, and share accounting.
- Uses mainnet forking for realistic tests.

### JavaScript Integration
- Located in `contracts/integration-tests/VelodromeLiquidityManager.test.js`.
- Uses ethers.js and Tenderly for transaction simulation and mainnet forking.
- Demonstrates real deposit flows and error handling.

## Development Workflow

See [contracts/README.md](contracts/README.md) for full Foundry usage, including:
- Build: `forge build`
- Test: `forge test`
- Format: `forge fmt`
- Deploy: `forge script ...`
- Anvil (local node): `anvil`
- Cast (CLI): `cast <subcommand>`

## Acknowledgements
- Inspired by Uniswap V3 and Velodrome concentrated liquidity models.
- Uses Foundry for Solidity development and testing.
- Thanks to the open-source DeFi and Ethereum community for tools and inspiration.

---

For more details, see the contract NatSpec comments and the test files. PRs and issues welcome!
