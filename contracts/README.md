# Vaquita Lisk

# VaquitaPool & VelodromeLiquidityManager

Vaquita Lisk is a robust, modular smart contract system for managing user deposits and liquidity provisioning in Uniswap V3/Velodrome-style concentrated liquidity pools. It features a user-facing `VaquitaPool` contract and a core `VelodromeLiquidityManager`, both upgradeable and pausable, enabling secure, flexible, and future-proof DeFi operations.

This project is designed for advanced DeFi protocols and power users who want to abstract away the complexity of managing Uniswap V3/Velodrome positions, while maintaining transparency, modularity, and extensibility.

## Key Features

- **Upgradeable & Modular**: Both `VaquitaPool` and `VelodromeLiquidityManager` are upgradeable using OpenZeppelin's TransparentUpgradeableProxy pattern, allowing for seamless upgrades and maintenance.
- **Pausable & Ownable**: Emergency stop and admin controls for all critical contracts using OpenZeppelin's `PausableUpgradeable` and `OwnableUpgradeable`.
- **Single-Token Deposit**: Users deposit tokenA, half is swapped for tokenB, and both are added as liquidity to a Uniswap V3/Velodrome position.
- **Share-Based Accounting**: Each deposit is tracked with shares, allowing precise proportional withdrawals and fair reward distribution.
- **UUID Tracking**: Every deposit is associated with a unique `bytes16` ID for easy lookup and management.
- **Modular Withdrawals**: On withdrawal, liquidity is removed, tokens are collected, and tokenB can be swapped back to tokenA before returning to the user.
- **Multi-User Support**: Each user can have multiple deposits, tracked independently.
- **Gas-Efficient Approvals**: Uses the approve-once pattern for router and position manager.
- **Events**: Emits `DepositMade` and `Withdrawn` events for off-chain tracking and analytics.
- **Extensive Testing & Coverage**: Comprehensive Foundry-based Solidity tests, script coverage, and PDF export for audit readiness.

## Contract Structure

- `contracts/src/VaquitaPool.sol`: Main user-facing contract, upgradeable, pausable, and ownable. Manages user deposits, withdrawals, rewards, and integrates with the liquidity manager.
- `contracts/src/VelodromeLiquidityManager.sol`: Core contract implementing all liquidity logic, also upgradeable and pausable.
- `contracts/src/interfaces/external/IUniversalRouter.sol`: Minimal interface for the Universal Router (swaps).
- `contracts/src/interfaces/external/INonFungiblePositionManager.sol`: Minimal interface for Uniswap V3/Velodrome position manager.
- `contracts/test/VelodromeLiquidityManager.t.sol`, `contracts/test/VaquitaPool.t.sol`, `contracts/test/ProxyDeploymentAndUpgrade.t.sol`: Comprehensive Foundry test suites (multi-user, edge cases, upgradeability, pausing, etc).
- `contracts/test/ScriptRun.t.sol`: Tests for all deployment and upgrade scripts to ensure full coverage.

## How It Works

### Deployment & Upgradeability
- Deploy `VaquitaPool` and `VelodromeLiquidityManager` as upgradeable proxies using OpenZeppelin's TransparentUpgradeableProxy and ProxyAdmin.
- Initialization is handled via `initialize` functions (no constructors).
- Upgrades are performed via ProxyAdmin, with tests covering upgrade and re-initialization flows.

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

### Share & UUID Tracking
- Each deposit is tracked by UUID and user address.
- Users can query their deposits and shares at any time.

## Testing & Coverage

### Solidity (Foundry)
- Located in `contracts/test/`.
- Covers single and multi-user scenarios, edge cases, share accounting, pausing, upgradeability, and proxy admin flows.
- Uses mainnet forking for realistic tests.
- Includes tests for all deployment and upgrade scripts to ensure operational reliability.

### Coverage & Audit Readiness
- Generates LCOV and HTML coverage reports for all contracts and scripts.
- Includes a script to export all coverage sections to a single PDF for audit and documentation.
- Follows best practices for upgradeable contracts, access control, and error handling.

## Development Workflow

See [contracts/README.md](README.md) for full Foundry usage, including:
- Build: `forge build`
- Test: `forge test`
- Coverage: `forge coverage --ir-minimum --report lcov && genhtml lcov.info --output-directory coverage-report`
- Export Coverage to PDF: `./generate-report.sh`
- Format: `forge fmt`
- Deploy: `forge script ...`
- Anvil (local node): `anvil`
- Cast (CLI): `cast <subcommand>`

## Security & Audit
- **OpenZeppelin Upgradeable Contracts**: All upgradeable logic uses industry-standard libraries.
- **Pausable & Ownable**: Emergency stop and admin controls for all critical contracts.
- **Custom Errors & Events**: Gas-efficient error handling and full event logging for transparency.
- **Audit-Ready**: Codebase is structured and documented for third-party security review.

## Acknowledgements
- Inspired by Uniswap V3 and Velodrome concentrated liquidity models.
- Uses Foundry for Solidity development and testing.
- Thanks to the open-source DeFi and Ethereum community for tools and inspiration.

---

For more details, see the contract NatSpec comments and the test files. PRs and issues welcome!
