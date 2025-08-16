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


帮我参考@contracts/MultiTokenPiggy.sol文件并增加一个新的合约文件，我的要求需要遵循以下草案同时满足基本的使用需求：

# 韭菜庄园合约使用规则（草案）

## 1. 使用资格
- 用户需支付一定费用购买后，方可创建并使用自己的韭菜庄园。
- 庄园资格不可转让。

## 2. 资产存入与锁定
- 用户首次存入 WBTC 时，需指定锁定期，到期前资产不可提取。
- 锁定期一旦设定，不可更改。
- 后续追加存入的资产，与首次存入共用同一到期时间。
- 到期后，用户需先提取全部余额，再开始新一期（重新指定锁定期）。

## 3. 继承人设定
- 庄园主人可设置最多 10 位继承人。
- 继承人必须已拥有自己的韭菜庄园。
- 每次修改继承人名单，需间隔 30 天；若需强制提前修改，则需支付额外费用。
- 修改行为包括新增、删除或更换任意继承人。

## 4. 活跃时间
- 用户进行以下任一操作时，会刷新其活跃时间：
    1. 存入资金（包括 0 金额）；
    2. 修改继承人；
    3. 其他会导致庄园状态变化的操作。
- 仅用户本人可刷新自己的活跃时间，他人无权代为刷新。
- 默认不活跃阈值为 1 年，从最近一次活跃时间起算。

## 5. 资金提取
- 资产到期后，资金可被提取。
- 在任意时刻，只有一人拥有提取资格：
    1. 若庄园主人活跃，则仅主人可提取；
    2. 若主人不活跃，则从继承人名单依次查找第一位活跃者，该继承人获得全部资金提取权；
    3. 若主人及所有继承人均不活跃，则由合约指定的“兜底地址”（如公益组织、基金会或平台自身）获得提取权；
    4. 若上述角色均不活跃或未配置，则无人可提取，直到出现新的活跃者。
- 提取为一次性全额提取，不支持部分提取。

## 6. 继承期间的维护
- 当某位继承人因前序成员全部不活跃而获得提取资格时，该继承人同时获得维护权限：
    - 仅可新增或删除排在自己之后的继承人；
    - 不得修改自己及之前的继承人。
- 该维护操作同样受“一个月一次 / 付费强制修改”的约束。

---

📌 **说明**  
以上规则旨在以最简洁的方式保障用户资金安全。  
核心逻辑为：**单一期锁定 → 活跃心跳 → 顺序唯一提取 → 后续断代继承 → 兜底提取**。
