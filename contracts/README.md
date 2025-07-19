# Vaquita Lisk

# VaquitaPool & VelodromeLiquidityManager

Vaquita Lisk is a robust, modular smart contract system for managing user deposits and liquidity provisioning in Uniswap V3/Velodrome-style concentrated liquidity pools. It features a user-facing `VaquitaPool` contract and a core `VelodromeLiquidityManager`, both upgradeable and pausable, enabling secure, flexible, and future-proof DeFi operations.

This project is designed for advanced DeFi protocols and power users who want to abstract away the complexity of managing Uniswap V3/Velodrome positions, while maintaining transparency, modularity, and extensibility.

## Key Features

- **Upgradeable & Modular**: Both `VaquitaPool` and `VelodromeLiquidityManager` are upgradeable using OpenZeppelin's TransparentUpgradeableProxy pattern, allowing for seamless upgrades and maintenance.
- **Pausable & Ownable**: Emergency stop and admin controls for all critical contracts using OpenZeppelin's `PausableUpgradeable` and `OwnableUpgradeable`.
- **Single-Token Deposit**: Users deposit USDC.e, half is swapped for USDT, and both are added as liquidity to a Uniswap V3/Velodrome position.
- **Share-Based Accounting**: Each deposit is tracked with shares, allowing precise proportional withdrawals and fair reward distribution.
- **UUID Tracking**: Every deposit is associated with a unique `bytes16` ID for easy lookup and management.
- **Lock Period System**: Configurable lock periods with reward distribution based on deposit duration.
- **Early Withdrawal Fees**: Configurable fees for early withdrawals to incentivize long-term participation.
- **Reward Pool Management**: Automated reward distribution and protocol fee collection.
- **EIP-2612 Permit Support**: Gasless token approvals for improved user experience.
- **Multi-User Support**: Each user can have multiple deposits, tracked independently.
- **Gas-Efficient Approvals**: Uses the approve-once pattern for router and position manager.
- **Events**: Comprehensive event logging for off-chain tracking and analytics.
- **Extensive Testing & Coverage**: Comprehensive Foundry-based Solidity tests, script coverage, and PDF export for audit readiness.

## Contract Structure

- `contracts/src/VaquitaPool.sol`: Main user-facing contract, upgradeable, pausable, and ownable. Manages user deposits, withdrawals, rewards, lock periods, and integrates with the liquidity manager.
- `contracts/src/VelodromeLiquidityManager.sol`: Core contract implementing all liquidity logic, also upgradeable and pausable.
- `contracts/src/interfaces/IVelodromeLiquidityManager.sol`: Interface for the liquidity manager contract.
- `contracts/src/interfaces/IPermit.sol`: Interface for EIP-2612 permit functionality.
- `contracts/src/interfaces/external/IUniversalRouter.sol`: Minimal interface for the Universal Router (swaps).
- `contracts/src/interfaces/external/INonFungiblePositionManager.sol`: Minimal interface for Uniswap V3/Velodrome position manager.
- `contracts/src/interfaces/external/IUniswapV3Pool.sol`: Interface for Uniswap V3 pool interactions.
- `contracts/test/VelodromeLiquidityManager.t.sol`, `contracts/test/VaquitaPool.t.sol`, `contracts/test/ProxyDeploymentAndUpgrade.t.sol`: Comprehensive Foundry test suites (multi-user, edge cases, upgradeability, pausing, etc).
- `contracts/test/ScriptRun.t.sol`: Tests for all deployment and upgrade scripts to ensure full coverage.

## How It Works

### Deployment & Upgradeability
- Deploy `VaquitaPool` and `VelodromeLiquidityManager` as upgradeable proxies using OpenZeppelin's TransparentUpgradeableProxy and ProxyAdmin.
- Initialization is handled via `initialize` functions (no constructors).
- Upgrades are performed via ProxyAdmin, with tests covering upgrade and re-initialization flows.

### Deposit
- User calls `deposit(bytes16 depositId, uint256 amount, uint256 period, uint256 deadline, bytes memory signature)` with a unique ID, amount of USDC.e, lock period, and EIP-2612 permit data.
- Contract validates the deposit and lock period.
- USDC.e is transferred to the contract and supplied to the VelodromeLiquidityManager.
- Shares are minted and tracked per user/deposit with lock period information.
- Position is created with entry time and finalization time based on lock period.
- Emits `FundsDeposited` event.

### Withdrawal
- User calls `withdraw(bytes16 depositId)`.
- Contract checks if withdrawal is early or after lock period completion.
- For early withdrawals: applies early withdrawal fee and adds remaining interest to reward pool.
- For late withdrawals: calculates and distributes rewards from the reward pool.
- Liquidity is removed from Velodrome, tokens are collected, and USDT is swapped back to USDC.e.
- User receives their share of USDC.e plus any earned rewards.
- Position record is marked as inactive, and `FundsWithdrawn` event is emitted.

### Reward System
- **Lock Periods**: Configurable time periods that determine reward eligibility.
- **Reward Pools**: Separate reward pools for each lock period.
- **Early Withdrawal Fees**: Configurable fees (in basis points) for early withdrawals.
- **Protocol Fees**: Automated collection of fees for protocol sustainability.
- **Share-Based Distribution**: Rewards distributed proportionally based on user shares and lock period.

### Share & UUID Tracking
- Each deposit is tracked by UUID and user address.
- Users can query their positions and shares at any time.
- Lock period information is stored with each position.
- Total deposits and shares are tracked per lock period.

## Configuration

### Token Configuration
- **Primary Token**: USDC.e (0xF242275d3a6527d877f2c927a82D9b057609cc71)
- **Secondary Token**: USDT (0x05D032ac25d322df992303dCa074EE7392C117b9)
- **Liquidity Pair**: USDC.e/USDT concentrated liquidity

### Velodrome Integration
- **Universal Router**: 0x652e53C6a4FE39B6B30426d9c96376a105C89A95
- **Position Manager**: 0x991d5546C4B442B4c5fdc4c8B8b8d131DEB24702
- **Tick Configuration**: Configurable tick spacing, lower, and upper bounds

### Default Settings
- **Lock Period**: 1 week (configurable)
- **Early Withdrawal Fee**: 0% (configurable)
- **Basis Points**: 10,000 (100%)

## Testing & Coverage

### Solidity (Foundry)
- Located in `contracts/test/`.
- Covers single and multi-user scenarios, edge cases, share accounting, pausing, upgradeability, and proxy admin flows.
- Tests lock period functionality, early withdrawal fees, and reward distribution.
- Uses mainnet forking for realistic tests.
- Includes tests for all deployment and upgrade scripts to ensure operational reliability.

### Coverage & Audit Readiness
- Generates LCOV and HTML coverage reports for all contracts and scripts.
- Includes a script to export all coverage sections to a single PDF for audit and documentation.
- Follows best practices for upgradeable contracts, access control, and error handling.

## Development Workflow

Foundry usage includes:
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
- **Reentrancy Protection**: All external calls are protected against reentrancy attacks.
- **EIP-2612 Permit**: Secure gasless approval mechanism.
- **Audit-Ready**: Codebase is structured and documented for third-party security review.

## Contract Verification

The contracts can be verified on Blockscout using the following command:

```bash
forge verify-contract <CONTRACT_ADDRESS> lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol:TransparentUpgradeableProxy --constructor-args $(cast abi-encode "constructor(address,address,bytes)" <IMPLEMENTATION_ADDRESS> <ADMIN_ADDRESS> <INIT_DATA>) --verifier blockscout --verifier-url https://blockscout.lisk.com/api --chain-id 1135 --etherscan-api-key <API_KEY>
```

## Acknowledgements
- Inspired by Uniswap V3 and Velodrome concentrated liquidity models.
- Uses Foundry for Solidity development and testing.
- Thanks to the open-source DeFi and Ethereum community for tools and inspiration.

---

For more details, see the contract NatSpec comments and the test files. PRs and issues welcome!