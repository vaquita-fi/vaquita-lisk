# Vaquita Lisk

# Save to Earn Protocol on Lisk

Vaquita Lisk is an innovative **Save to Earn** protocol built on the Lisk blockchain, seamlessly integrated with Velodrome's concentrated liquidity pools. The protocol enables users to earn rewards simply by saving and providing liquidity, creating a sustainable ecosystem where saving becomes a profitable activity.

## 🎯 Core Concept

The Save to Earn model incentivizes users to maintain their deposits over time, rewarding them for their commitment to the ecosystem. By integrating with Velodrome's advanced concentrated liquidity management, users can maximize their yield while contributing to the overall liquidity of the Lisk DeFi ecosystem.

## 🏗️ Architecture Overview

### Smart Contract Layer
- **VaquitaPool**: The main user-facing contract, upgradeable via OpenZeppelin's TransparentUpgradeableProxy pattern. Handles user deposits, withdrawals, reward distribution, and integrates with the liquidity manager. Features pausable and ownable access control for security and upgradability.
- **VelodromeLiquidityManager**: Core contract managing user deposits and liquidity provisioning, also upgradeable and pausable.
- **Automated Liquidity Management**: Handles complex Uniswap V3/Velodrome position management
- **Share-Based Accounting**: Precise tracking of user contributions and rewards using shares, ensuring fair and transparent distribution.
- **UUID-Based Deposit Tracking**: Each deposit is tracked with a unique identifier (UUID), allowing for flexible and independent management of multiple deposits per user.
- **Upgradeable & Modular**: All core contracts are upgradeable using OpenZeppelin's upgradeable contracts, allowing for future enhancements and security patches without redeployment.

### Key Features
- **Single-Token Deposits**: Users deposit LSK tokens, automatically converted to optimal liquidity positions
- **Concentrated Liquidity**: Leverages Velodrome's advanced liquidity management for maximum efficiency
- **Reward Distribution**: Earn rewards based on deposit duration and amount
- **Flexible Withdrawals**: Users can withdraw their deposits and accumulated rewards at any time
- **Gas Optimization**: Efficient smart contracts designed for cost-effective operations
- **Pausable**: Both VaquitaPool and VelodromeLiquidityManager can be paused by the owner for emergency response
- **Upgradeable**: Proxy pattern allows seamless upgrades and maintenance

## 💰 Economic Model

### Save to Earn Mechanics
1. **Deposit Phase**: Users deposit LSK tokens into the protocol
2. **Liquidity Provision**: Tokens are automatically deployed to Velodrome concentrated liquidity pools
3. **Reward Accumulation**: Users earn rewards based on:
   - Deposit amount
   - Time held in the protocol
   - Pool performance and fees
4. **Withdrawal**: Users can withdraw their original deposit plus accumulated rewards

### Reward Sources
- **Trading Fees**: Share of fees from Velodrome pool transactions
- **Protocol Rewards**: Additional incentives for long-term savers
- **Liquidity Mining**: Rewards for providing essential liquidity to the ecosystem

## 🔧 Technical Implementation

### Smart Contract Features
- **VaquitaPool**: Upgradeable, pausable, and ownable. Manages user positions, rewards, and integrates with the liquidity manager. Uses share-based accounting and UUID tracking for deposits.
- **VelodromeLiquidityManager**: Upgradeable, pausable, and ownable. Manages liquidity provisioning and interacts with external protocols.
- **UUID Tracking**: Each deposit has a unique identifier for precise management
- **Modular Design**: Extensible architecture for future enhancements
- **Security First**: Comprehensive testing and audit-ready codebase
- **Gas Efficient**: Optimized for cost-effective operations on Lisk
- **Upgradeable Proxy Pattern**: All main contracts use OpenZeppelin's TransparentUpgradeableProxy for safe upgrades
- **Pausable**: Emergency stop mechanism for both core contracts

### Integration Points
- **Velodrome Protocol**: Direct integration with concentrated liquidity pools
- **Universal Router**: Seamless token swaps and routing
- **Position Management**: Automated handling of complex liquidity positions

## 🧪 Testing & Coverage

- **Comprehensive Solidity Tests**: All core logic is covered by Solidity-based tests using Foundry, including deposit/withdrawal flows, pausing, upgrades, and edge cases.
- **Upgradeable & Proxy Tests**: Deployment, initialization, and upgrade flows are thoroughly tested to ensure safe upgradability.
- **Coverage Reports**: LCOV and HTML coverage reports are generated for all contracts, including scripts, with tools to export to PDF for audit and documentation.
- **Script Coverage**: All deployment and upgrade scripts are tested for coverage, ensuring reliability of operational tooling.
- **Test Utilities**: Reusable helpers for mocking, UUID generation, and fee simulation.
- **Audit-Ready**: Codebase follows best practices for upgradeable contracts, access control, and error handling.

## 🚀 Benefits for Users

### For Savers
- **Passive Income**: Earn rewards simply by saving
- **Liquidity Access**: Maintain access to funds while earning
- **Risk Management**: Diversified exposure through professional liquidity management
- **Transparency**: Full visibility into deposit status and rewards

### For the Ecosystem
- **Increased Liquidity**: More liquid markets for Lisk tokens
- **User Retention**: Incentivizes long-term participation
- **Protocol Growth**: Sustainable expansion through save-to-earn mechanics

## 📊 Use Cases

### Individual Savers
- Long-term wealth accumulation
- Passive income generation
- Portfolio diversification

### DeFi Participants
- Liquidity provision with simplified management
- Yield optimization through concentrated liquidity
- Risk-adjusted returns

### Protocol Integrators
- Building on top of the save-to-earn infrastructure
- Creating additional reward mechanisms
- Developing complementary DeFi products

## 🛡️ Security & Audit
- **OpenZeppelin Upgradeable Contracts**: All upgradeable logic uses industry-standard libraries.
- **Pausable & Ownable**: Emergency stop and admin controls for all critical contracts.
- **Custom Errors & Events**: Gas-efficient error handling and full event logging for transparency.
- **Audit-Ready**: Codebase is structured and documented for third-party security review.

## 🧪 How to Run Tests & Generate Coverage

1. **Run all tests:**
   ```sh
   forge test
   ```
2. **Generate coverage report:**
   ```sh
   forge coverage --ir-minimum --report lcov && genhtml lcov.info --output-directory coverage-report
   ```
3. **Export coverage to PDF (all sections):**
   ```sh
   ./generate-report.sh
   ```

---

For more details, see the contract source files and test suite.
