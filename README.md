# Abokiv2

Abokiv2 is a smart contract protocol for decentralized cryptocurrency exchange orders, built on Base mainnet. The protocol leverages Uniswap V3 for optimal token routing, offering improved security, better swap routes, and reduced fees compared to its predecessor.

## Overview

The protocol enables users to create exchange orders that are automatically processed through Uniswap V3 liquidity pools. It supports direct token transfers, ETH to token swaps, and custom multi hop token paths, all while collecting a configurable protocol fee for sustainability.

## Deployed Contract

| Network | Contract Address | Chain ID |
|---------|-----------------|----------|
| Base Mainnet | `0xdce30460bf7d277fe0bb01db45090d1cfa89d74a` | 8453 |

## Features

### Order Creation
Users can create exchange orders through three primary methods:

**Direct Token Orders**
Transfer supported tokens directly to a designated liquidity provider. The protocol deducts a fee and forwards the remaining tokens to the specified recipient.

**ETH to Token Swaps**
Send ETH to the contract, which automatically wraps it to WETH and swaps through Uniswap V3 to the desired output token. Failed swaps trigger automatic refunds.

**Custom Path Orders**
Execute multi hop swaps through a user specified token path. This enables more complex routing for better rates on certain token pairs.

### Fee Structure
The protocol collects fees in basis points (1 basis point = 0.01%). The maximum configurable fee is 1000 basis points (10%). Fees are sent to a designated treasury address.

### Uniswap V3 Integration
The contract integrates with Uniswap V3 and supports all standard fee tiers:
| Fee Tier | Description |
|----------|-------------|
| 100 | 0.01% (stable pairs) |
| 500 | 0.05% (stable pairs) |
| 3000 | 0.30% (most pairs) |
| 10000 | 1.00% (exotic pairs) |

The default fee tier is 3000 (0.30%), which can be adjusted by the contract owner.

## Technical Architecture

### Dependencies
| Component | Address |
|-----------|---------|
| Uniswap V3 Router | `0x2626664c2603336E57B271c5C0b26F421741e481` |
| Quoter V2 | `0x3d4e44Eb1374240CE5F1B871ab261CD16335B76a` |
| WETH | `0x4200000000000000000000000000000000000006` |

### Supported Tokens
| Token | Address |
|-------|---------|
| USDC (Native) | `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` |
| USDbC (Bridged) | `0xd9aAEc86B65D86f6A7B5B1b0c42FFA531710b6CA` |

Additional tokens can be enabled by the contract owner through the `setTokenSupport` function.

### Security Features
The contract implements several security measures:

**Reentrancy Protection**
All state changing functions are protected against reentrancy attacks using a mutex pattern.

**Ownership Controls**
Administrative functions are restricted to the contract owner, including treasury updates, fee adjustments, and token whitelisting.

**Input Validation**
All user inputs are validated for zero addresses, minimum amounts, and supported tokens before processing.

**Automatic Refunds**
Failed swaps trigger automatic refunds to the designated refund address, preventing loss of user funds.

## Development Setup

### Prerequisites
Install Foundry by following the instructions at [book.getfoundry.sh](https://book.getfoundry.sh/getting-started/installation).

### Installation
Clone the repository and install dependencies:
```
git clone <repository_url>
cd abokiv2-fresh
forge install
```

### Environment Configuration
Create a `.env` file with the following variables:
```
TREASURY_ADDRESS=<your_treasury_address>
PROTOCOL_FEE_PERCENT=<fee_in_basis_points>
BASESCAN_API_KEY=<your_basescan_api_key>
PRIVATE_KEY=<deployer_private_key>
```

### Build
Compile the smart contracts:
```
forge build
```

### Test
Run the test suite:
```
forge test
```

Run tests with verbosity for debugging:
```
forge test -vvvv
```

### Gas Snapshots
Generate gas usage reports:
```
forge snapshot
```

### Format
Format the Solidity code:
```
forge fmt
```

## Deployment

### Local Deployment
Start a local Anvil node:
```
anvil
```

Deploy to local network:
```
forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --broadcast
```

### Base Mainnet Deployment
Deploy to Base mainnet:
```
forge script script/Deploy.s.sol:DeployAbokiv2 --rpc-url https://mainnet.base.org --broadcast --verify
```

### Contract Verification
Verify on Basescan:
```
forge verify-contract <contract_address> src/Abokiv2.sol:Abokiv2 --chain base --watch
```

## Contract Interface

### Core Functions

**createOrder**
Create an order by transferring supported tokens directly.
```solidity
function createOrder(
    address _token,
    uint256 _amount,
    uint256 _rate,
    address _refundAddress,
    address _liquidityProvider
) external returns (uint256 orderId)
```

**createOrderWithSwap**
Create an order by swapping ETH to a target token.
```solidity
function createOrderWithSwap(
    address _targetToken,
    uint256 _minOutputAmount,
    uint256 _rate,
    address _refundAddress,
    address _liquidityProvider
) external payable returns (uint256 orderId)
```

**createOrderWithCustomPath**
Create an order using a custom token swap path.
```solidity
function createOrderWithCustomPath(
    address[] calldata _path,
    uint256 _inputAmount,
    uint256 _minOutputAmount,
    uint256 _rate,
    address _refundAddress,
    address _liquidityProvider
) external returns (uint256 orderId)
```

### View Functions

**estimateSwapOutput**
Get an estimate for a direct swap.
```solidity
function estimateSwapOutput(
    address _inputToken,
    address _targetToken,
    uint256 _inputAmount
) external returns (uint256)
```

**estimateSwapOutputWithPath**
Get an estimate for a multi hop swap.
```solidity
function estimateSwapOutputWithPath(
    address[] calldata _path,
    uint256 _inputAmount
) external returns (uint256)
```

**getOrderInfo**
Retrieve details of a specific order.
```solidity
function getOrderInfo(uint256 _orderId) external view returns (
    address token,
    uint256 amount,
    uint256 rate,
    address creator,
    address refundAddress,
    address liquidityProvider,
    bool isFulfilled,
    bool isRefunded,
    uint256 timestamp
)
```

### Administrative Functions

| Function | Description |
|----------|-------------|
| `setUniswapRouter(address)` | Update the Uniswap V3 router address |
| `setQuoter(address)` | Update the Quoter V2 address |
| `setWETH(address)` | Update the WETH address |
| `setTokenSupport(address, bool)` | Enable or disable a token |
| `setFeeTierSupport(uint24, bool)` | Enable or disable a fee tier |
| `setDefaultFeeTier(uint24)` | Set the default fee tier for swaps |
| `setTreasury(address)` | Update the treasury address |
| `setProtocolFeePercent(uint256)` | Update the protocol fee |
| `transferOwnership(address)` | Transfer contract ownership |

## Events

The contract emits the following events for off chain tracking:

| Event | Description |
|-------|-------------|
| `OrderCreated` | Emitted when a new order is created |
| `OrderFulfilled` | Emitted when an order is fulfilled |
| `OrderRefunded` | Emitted when an order is refunded |
| `SwapExecuted` | Emitted when a swap is completed |
| `TokenSupportUpdated` | Emitted when token support status changes |
| `TreasuryUpdated` | Emitted when treasury address changes |
| `ProtocolFeeUpdated` | Emitted when protocol fee changes |
| `RouterUpdated` | Emitted when router address changes |
| `WETHUpdated` | Emitted when WETH address changes |
| `QuoterUpdated` | Emitted when quoter address changes |
| `FeeTierUpdated` | Emitted when fee tier support changes |
| `DefaultFeeTierUpdated` | Emitted when default fee tier changes |

did an audit find the full details about commit here  https://github.com/Svector-anu/Abokiv2contract/commit/e840cc1086a20bfc115604b7bbf080ddb66cecef#diff-bac2a3206914c55b0d31923b9d101f6eabfe6eddaedb37da63a7d61d70e71b47
## License

This project is licensed under the MIT License.
