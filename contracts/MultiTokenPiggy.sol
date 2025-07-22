// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";


/**
 * ██████╗ ██╗ ██████╗  ██████╗██╗   ██╗██████╗  ██████╗ ███████╗
 * ██╔══██╗██║██╔════╝ ██╔════╝╚██╗ ██╔╝╚════██╗██╔════╝ ██╔════╝
 * ██████╔╝██║██║  ███╗██║  ███╗╚████╔╝  █████╔╝███████╗ ███████╗
 * ██╔═══╝ ██║██║   ██║██║   ██║ ╚██╔╝   ╚═══██╗██╔═══██╗╚════██║
 * ██║     ██║╚██████╔╝╚██████╔╝  ██║   ██████╔╝╚██████╔╝███████║
 * ╚═╝     ╚═╝ ╚═════╝  ╚═════╝   ╚═╝   ╚═════╝  ╚═════╝ ╚══════╝
 * 
 * @title PIGGY365 - 多代币存钱罐合约
 * @dev 实现一个支持多种ERC20代币的去中心化存钱罐系统，集成Permit2
 * 
 */

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
contract MultiTokenPiggy is Ownable, ReentrancyGuard {
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

    /// @dev Emergency pause state
    bool public paused = false;

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
    event WithdrawFailed(
        address indexed user,
        address indexed token,
        uint256 amount,
        string reason
    );
    event TokenRemoved(
        address indexed user,
        address indexed token,
        uint256 amount
    );
    event Paused(address indexed by);
    event Unpaused(address indexed by);

    IPermit2 public immutable permit2;

    modifier notPaused() {
        require(!paused, "Contract is paused");
        _;
    }

    constructor(address permit2Address) Ownable(msg.sender) {
        require(permit2Address != address(0), "Invalid Permit2 address");
        permit2 = IPermit2(permit2Address);
    }

    /// @notice Emergency pause the contract
    function pause() external onlyOwner {
        paused = true;
        emit Paused(msg.sender);
    }

    /// @notice Unpause the contract
    function unpause() external onlyOwner {
        paused = false;
        emit Unpaused(msg.sender);
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
    /// @param lockPeriod Lock period (in seconds), only effective when creating for the first time
    /// @param amount Amount of tokens to deposit
    /// @param permit Permit2 permission struct
    /// @param signature Permit2 signature
    function deposit(
        uint256 lockPeriod,
        uint256 amount,
        IPermit2.PermitTransferFrom calldata permit,
        bytes calldata signature
    ) external nonReentrant notPaused {
        address token = permit.permitted.token;
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
    function withdraw() external nonReentrant notPaused {
        PiggyBank storage bank = piggyBanks[msg.sender];
        require(bank.exists, "Please create a piggy bank first");
        require(
            block.timestamp >= bank.createdAt + bank.lockPeriod,
            "Not yet unlocked"
        );

        address[] memory tokens = userTokens[msg.sender];

        // 先更新所有状态，防止重入攻击
        uint256[] memory amounts = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            amounts[i] = bank.balances[tokens[i]];
            bank.balances[tokens[i]] = 0;
        }

        // 再进行转账，跳过失败的代币
        for (uint256 i = 0; i < tokens.length; i++) {
            if (amounts[i] == 0) continue;
            address token = tokens[i];
            try IERC20(token).transfer(msg.sender, amounts[i]) returns (
                bool success
            ) {
                if (success) {
                    emit Withdrawn(msg.sender, token, amounts[i]);
                } else {
                    // 转账失败，恢复余额
                    bank.balances[token] = amounts[i];
                    emit WithdrawFailed(
                        msg.sender,
                        token,
                        amounts[i],
                        "Transfer returned false"
                    );
                }
            } catch Error(string memory reason) {
                // 转账异常，恢复余额
                bank.balances[token] = amounts[i];
                emit WithdrawFailed(msg.sender, token, amounts[i], reason);
            } catch {
                // 转账异常（无错误信息），恢复余额
                bank.balances[token] = amounts[i];
                emit WithdrawFailed(
                    msg.sender,
                    token,
                    amounts[i],
                    "Transfer failed"
                );
            }
        }
    }

    /// @notice Remove a problematic token from user's piggy bank (emergency function)
    /// @param token The token address to remove
    /// @dev This function allows users to remove tokens that are causing withdrawal issues
    function removeToken(address token) external nonReentrant notPaused {
        PiggyBank storage bank = piggyBanks[msg.sender];
        require(bank.exists, "Please create a piggy bank first");
        require(
            userHasToken[msg.sender][token],
            "Token not found in piggy bank"
        );

        uint256 amount = bank.balances[token];
        require(amount > 0, "No balance for this token");

        // 清除余额
        bank.balances[token] = 0;

        // 从用户代币列表中移除
        address[] storage tokens = userTokens[msg.sender];
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == token) {
                tokens[i] = tokens[tokens.length - 1];
                tokens.pop();
                break;
            }
        }
        userHasToken[msg.sender][token] = false;

        emit TokenRemoved(msg.sender, token, amount);
    }

    /// @notice 获取用户所有代币的余额信息
    /// @param user 用户地址
    /// @return tokens 代币地址数组
    /// @return balances 对应的余额数组
    function getAllBalances(
        address user
    )
        external
        view
        returns (address[] memory tokens, uint256[] memory balances)
    {
        tokens = userTokens[user];
        balances = new uint256[](tokens.length);

        PiggyBank storage bank = piggyBanks[user];
        for (uint256 i = 0; i < tokens.length; i++) {
            balances[i] = bank.balances[tokens[i]];
        }
    }
}
