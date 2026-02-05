# Abokiv2 Protocol

**Abokiv2** is a decentralized exchange (DEX) order management protocol deployed on the **Base Mainnet**. It facilitates secure, automated swaps by leveraging Uniswap V3 liquidity while offering a structured framework for order creation and protocol fee management.

## 🏗 Architecture & Design

Abokiv2 serves as an execution layer between users and Uniswap V3. Key architectural components include:

* **Order Execution:** Atomic swap functionality via the Uniswap V3 Router.
* **Asset Whitelisting:** Administrative control over supported trading pairs to mitigate "dust" attacks and malicious token interactions.
* **Security Guards:** Implementation of OpenZeppelin's `ReentrancyGuard` and `Ownable` modules.
* **ETH/WETH Management:** Native handling of ETH through wrapping and unwrapping logic to ensure liquidity flow consistency.

## 📂 Project Structure

```text
abokiv2-fresh/
├── src/                # Core Logic
│   └── Abokiv2.sol     # Primary Protocol Contract
├── script/             # DevOps & Orchestration
│   └── Deploy.s.sol    # Deployment logic for Base/EVM chains
├── test/               # Quality Assurance
│   └── Abokiv2.t.sol   # Comprehensive unit and integration tests
├── lib/                # Dependencies (OpenZeppelin, Forge-std)
├── broadcast/          # On-chain transaction logs
└── foundry.toml        # Compiler & Network configurations

```

## 🚀 Getting Started

### Prerequisites

* [Foundry](https://getfoundry.sh/) (Forge, Cast, Anvil, Chisel)

### Installation

1. **Clone the repository:**
```bash
git clone <repository-url>
cd abokiv2-fresh

```


2. **Install dependencies:**
```bash
forge install

```



### Compilation

Build the smart contracts and generate ABIs:

```bash
forge build

```

## 🧪 Testing Suite

The protocol utilizes a robust test suite covering order lifecycle, edge cases, and administrative functions.

* **Unit Tests:** `forge test`
* **Trace Analysis:** `forge test -vvvv`
* **Coverage:** `forge coverage`
* **Targeted Testing:**
```bash
forge test --match-test test_CreateOrder

```



## 🛠 Deployment & Configuration

### Environment Setup

Create a `.env` file based on the provided template:

```bash
cp .env.example .env

```

| Variable | Description |
| --- | --- |
| `RPC_URL` | Base Mainnet RPC Endpoint |
| `PRIVATE_KEY` | Deployer Wallet Private Key |
| `ETHERSCAN_API_KEY` | For contract verification (BaseScan) |

### Execution

Run the deployment script:

```bash
source .env
forge script script/Deploy.s.sol:Deploy --rpc-url $RPC_URL --broadcast --verify -vvvv

```

## ⚖️ License

This project is licensed under the **MIT License**. See the [LICENSE](https://www.google.com/search?q=LICENSE) file for details.

---
