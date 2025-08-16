# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Piggy365 is a smart contract project implementing multiple savings systems:

1. **Multi-user ERC20 piggy bank system** - Users can create time-locked savings accounts using multiple ERC20 tokens, with deposits made via Permit2 signatures and withdrawals only allowed after the lock period expires.

2. **Scallion Manor inheritance system** - An advanced WBTC savings contract with inheritance features, where users purchase manor access and can set up to 10 inheritors with activity-based withdrawal rights.

## Development Commands

### Core Development
- `npm run build` - Compile smart contracts using Hardhat
- `npm run test` - Run comprehensive test suite
- `npm run node` - Start local Hardhat node for development
- `npm run format` - Format code using Prettier

### Contract Deployment
- `npm run deploy0` - Deploy to local Hardhat network
- `npm run deploy1` - Deploy to Sepolia testnet
- `npm run deploy2` - Deploy to World Chain Mainnet

### Testing Commands
- `npx hardhat test` - Run all tests
- `npx hardhat test test/MultiTokenPiggy.test.ts` - Run specific test file
- `npx hardhat coverage` - Generate test coverage report

## Smart Contract Architecture

### Core Contracts

**MultiTokenPiggy.sol** - Main contract supporting multiple ERC20 tokens
- Multi-token piggy bank with unified lock periods
- Permit2 integration for gasless deposits
- Emergency token removal functionality
- Reentrancy protection via OpenZeppelin's ReentrancyGuard

**Piggy.sol** - Single-token piggy bank (legacy/reference implementation)
- Single WLD token support
- Basic time-locked savings functionality

**ScallionManor.sol** - Advanced inheritance-based WBTC savings contract
- Paid manor access system with non-transferable qualifications
- WBTC-only deposits with time-lock functionality
- Inheritance system supporting up to 10 inheritors
- Activity-based withdrawal rights with 1-year inactivity threshold
- Inheritor management with 30-day cooldown or paid force changes
- Fallback address system for unclaimed funds
- Maintenance rights for active inheritors

**Key Features:**
- Time-locked savings with user-defined periods
- Automatic piggy bank creation on first deposit
- Multi-token support with unified lock periods (MultiTokenPiggy)
- Inheritance-based access control with activity monitoring (ScallionManor)
- Robust error handling for failed token transfers
- Reset functionality when all balances are zero after lock expiry
- Permit2 integration for gasless transactions

### Contract Integration Patterns

**Permit2 Integration:**
- Uses canonical Permit2 address: `0x000000000022D473030F116dDEE9F6B43aC78BA3`
- Gasless token transfers via signature-based approvals
- Standard token approval flow required before deposits

**State Management:**
- Struct-based piggy banks with mappings for token balances
- User token enumeration via `userTokens` mapping (MultiTokenPiggy)
- Manor-based inheritance system with activity tracking (ScallionManor)
- Event-driven architecture for deposit/withdrawal tracking
- Inheritor management with access validation

## Network Configuration

Supports multiple networks via Hardhat config:
- **hardhat**: Local development network
- **sepolia**: Ethereum Sepolia testnet
- **worldchainSepolia**: World Chain Sepolia testnet (Chain ID: 4801)
- **worldchainMainnet**: World Chain Mainnet (Chain ID: 480)

Environment variables required for testnet/mainnet deployment:
- `SEPOLIA_RPC_URL`, `SEPOLIA_PRIVATE_KEY`
- `MAINNET_PRIVATE_KEY`
- `ETHERSCAN_API_KEY` for contract verification

## Test Architecture

Comprehensive test suite in TypeScript using Hardhat framework:
- Mock Permit2 deployment to canonical address for testing
- Multiple test token contracts (USDT, USDC, DAI)
- Edge case testing including reentrancy protection
- Time manipulation for lock period testing

## Security Considerations

- ReentrancyGuard protection on state-changing functions
- Robust error handling with event emission for failed transfers
- Emergency token removal function for problematic tokens
- Standard Permit2 integration following best practices

## Development Notes

- Solidity version: 0.8.30 with optimizer enabled (200 runs)
- OpenZeppelin contracts for security primitives
- TypeChain integration for type-safe contract interactions
- Comprehensive test coverage including edge cases and security scenarios