# Abokiv2 Smart Contract

This directory contains the Foundry project for the Abokiv2 smart contract. The contract is deployed on Base mainnet and provides decentralized exchange order functionality through Uniswap V3.

## Quick Start

```
forge build
forge test
```

## Project Structure

```
abokiv2-fresh/
├── src/
│   └── Abokiv2.sol          # Main contract
├── script/
│   └── Deploy.s.sol         # Deployment script
├── test/
│   └── Abokiv2.t.sol        # Test suite
├── lib/
│   └── forge-std/           # Foundry standard library
├── broadcast/               # Deployment transaction records
├── foundry.toml             # Foundry configuration
└── .env.example             # Environment template
```

## Configuration

Copy `.env.example` to `.env` and fill in the required values before deployment.

## Deployment

The contract has been deployed to Base mainnet. See the parent README for full documentation.

## Testing

Run all tests:
```
forge test
```

Run with verbosity:
```
forge test -vvvv
```

Run specific test:
```
forge test --match-test test_CreateOrder
```

## License

MIT
