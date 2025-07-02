# Piggy365 Smart Contract

---

Welcome to the Piggy365 smart contract project! 

---

## 📝 Introduction

Piggy is a multi-user ERC20 piggy bank smart contract that allows users to create their own time-locked savings accounts using the WLD token. Users can deposit WLD into their personal piggy bank via Permit2 signatures, and can only withdraw the full balance after a user-defined lock period. Each user can only withdraw after the lock period has expired, ensuring disciplined savings. The contract leverages OpenZeppelin's IERC20 interface and integrates with Permit2 for secure and flexible token transfers.

## 🌟 Features

- Multi-user support: Each user can create and manage their own piggy bank.
- ERC20-based savings: Deposits and withdrawals are made using the WLD ERC20 token.
- Time-locked savings: Users set a lock period; funds can only be withdrawn after this period expires.
- Permit2 integration: Supports gasless and flexible token transfers via Permit2 signatures.
- Secure withdrawals: Only the full balance can be withdrawn, and only after the lock period.
- Automatic piggy bank creation: First deposit automatically creates a piggy bank for the user.
- Transparent and auditable: All actions are recorded on-chain with events for creation, deposit, and withdrawal.

