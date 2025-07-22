// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Permit2 interface definition
interface IPermit2 {
    struct TokenPermissions {
        address token;
        uint256 amount;
    }
    struct PermitTransferFrom {
        TokenPermissions permitted;
        uint256 nonce;
        uint256 deadline;
    }
    struct SignatureTransferDetails {
        address to;
        uint256 requestedAmount;
    }
    function permitTransferFrom(
        PermitTransferFrom calldata permit,
        SignatureTransferDetails calldata transferDetails,
        address owner,
        bytes calldata signature
    ) external;
}

/// @title Multi-token ERC20 Piggy Bank Contract (Multiple ERC20 + Permit2)
/// @author zhoufeng
/// @notice Users can create their own piggy bank for multiple ERC20 tokens, with unified lock period for all tokens
contract MultiTokenPiggy {
    /// @dev Piggy bank struct
    struct PiggyBank {
        uint256 createdAt;
        mapping(address => uint256) balances; // token address => balance
        bool exists;
        uint256 lockPeriod;
    }

    /// @dev Mapping to record each user's piggy bank
    mapping(address => PiggyBank) public piggyBanks;

    /// @dev Track user's tokens for enumeration
    mapping(address => address[]) public userTokens;
    mapping(address => mapping(address => bool)) public userHasToken;

    event PiggyBankCreated(address indexed user, uint256 createdAt);
    event Deposited(
        address indexed user,
        address indexed token,
        uint256 amount,
        uint256 newBalance
    );
    event Withdrawn(
        address indexed user,
        address indexed token,
        uint256 amount
    );

    IPermit2 public immutable permit2;
    address public constant PERMIT2_ADDRESS =
        0x000000000022D473030F116dDEE9F6B43aC78BA3;

    constructor() {
        permit2 = IPermit2(PERMIT2_ADDRESS);
    }

    /// @notice Query the balance of a specific token in user's piggy bank
    function getBalance(
        address user,
        address token
    ) external view returns (uint256) {
        return piggyBanks[user].balances[token];
    }

    /// @notice Query all tokens that user has deposited
    function getUserTokens(
        address user
    ) external view returns (address[] memory) {
        return userTokens[user];
    }

    /// @notice Query the unlock timestamp of a user's piggy bank
    /// @param user The user's address
    /// @return The unlock timestamp (in seconds)
    function getUnlockTimestamp(address user) external view returns (uint256) {
        PiggyBank storage bank = piggyBanks[user];
        require(bank.exists, "Piggy bank does not exist");
        return bank.createdAt + bank.lockPeriod;
    }

    /// @notice Check if user's piggy bank is unlocked
    function isUnlocked(address user) external view returns (bool) {
        PiggyBank storage bank = piggyBanks[user];
        if (!bank.exists) return false;
        return block.timestamp >= bank.createdAt + bank.lockPeriod;
    }

    /// @notice Deposit ERC20 tokens (first deposit automatically creates a piggy bank, uses Permit2 to transfer tokens)
    /// @param token The ERC20 token address to deposit
    /// @param lockPeriod Lock period (in seconds), only effective when creating for the first time
    /// @param amount Amount of tokens to deposit
    /// @param permit Permit2 permission struct
    /// @param signature Permit2 signature
    function deposit(
        address token,
        uint256 lockPeriod,
        uint256 amount,
        IPermit2.PermitTransferFrom calldata permit,
        bytes calldata signature
    ) external {
        require(amount > 0, "Deposit amount must be greater than 0");
        require(token != address(0), "Invalid token address");

        PiggyBank storage bank = piggyBanks[msg.sender];

        if (!bank.exists) {
            require(lockPeriod > 0, "Lock period must be greater than 0");
            bank.createdAt = block.timestamp;
            bank.exists = true;
            bank.lockPeriod = lockPeriod;
            emit PiggyBankCreated(msg.sender, block.timestamp);
        }

        // Check if all token balances are 0 and lock period has expired, reset creation time
        bool allBalancesZero = true;
        for (uint256 i = 0; i < userTokens[msg.sender].length; i++) {
            if (bank.balances[userTokens[msg.sender][i]] > 0) {
                allBalancesZero = false;
                break;
            }
        }

        if (
            allBalancesZero &&
            block.timestamp >= bank.createdAt + bank.lockPeriod
        ) {
            bank.createdAt = block.timestamp;
            bank.lockPeriod = lockPeriod;
            emit PiggyBankCreated(msg.sender, block.timestamp);
        }

        // Add token to user's token list if first time depositing this token
        if (!userHasToken[msg.sender][token]) {
            userTokens[msg.sender].push(token);
            userHasToken[msg.sender][token] = true;
        }

        // Permit2 transfer tokens
        permit2.permitTransferFrom(
            permit,
            IPermit2.SignatureTransferDetails({
                to: address(this),
                requestedAmount: amount
            }),
            msg.sender,
            signature
        );

        bank.balances[token] += amount;
        emit Deposited(msg.sender, token, amount, bank.balances[token]);
    }

    /// @notice Withdraw all tokens (can only withdraw after the lock period)
    function withdraw() external {
        PiggyBank storage bank = piggyBanks[msg.sender];
        require(bank.exists, "Please create a piggy bank first");
        require(
            block.timestamp >= bank.createdAt + bank.lockPeriod,
            "Not yet unlocked"
        );

        address[] memory tokens = userTokens[msg.sender];
        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            uint256 amount = bank.balances[token];
            if (amount > 0) {
                bank.balances[token] = 0;
                IERC20 tokenContract = IERC20(token);
                require(
                    tokenContract.transfer(msg.sender, amount),
                    "Transfer failed"
                );
                emit Withdrawn(msg.sender, token, amount);
            }
        }
    }

}
