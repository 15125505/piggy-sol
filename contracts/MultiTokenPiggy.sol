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
 * @title PIGGY365 - Multi-token Piggy Bank Contract
 * @dev Implements a decentralized piggy bank system supporting multiple ERC20 tokens, integrated with Permit2
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

    // Permit2 canonical address (same on all chains)
    IPermit2 public constant permit2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    constructor() Ownable(msg.sender) {
    }

    /// @notice Query the unlock timestamp of a user's piggy bank
    /// @param user The user's address
    /// @return The unlock timestamp (in seconds)
    function getUnlockTimestamp(address user) external view returns (uint256) {
        PiggyBank storage bank = piggyBanks[user];
        require(bank.exists, "Piggy bank does not exist");
        return bank.createdAt + bank.lockPeriod;
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
    ) external nonReentrant {
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
        if (bank.balances[token] == 0) {
            userTokens[msg.sender].push(token);
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
    function withdraw() external nonReentrant {
        PiggyBank storage bank = piggyBanks[msg.sender];
        require(bank.exists, "Please create a piggy bank first");
        require(
            block.timestamp >= bank.createdAt + bank.lockPeriod,
            "Not yet unlocked"
        );

        address[] memory tokens = userTokens[msg.sender];

        // Update all states first to prevent reentrancy attacks
        uint256[] memory amounts = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            amounts[i] = bank.balances[tokens[i]];
            bank.balances[tokens[i]] = 0;
        }

        // Then perform transfers, skipping failed tokens
        for (uint256 i = 0; i < tokens.length; i++) {
            if (amounts[i] == 0) continue;
            address token = tokens[i];
            try IERC20(token).transfer(msg.sender, amounts[i]) returns (
                bool success
            ) {
                if (success) {
                    emit Withdrawn(msg.sender, token, amounts[i]);
                } else {
                    // If transfer fails, restore balance
                    bank.balances[token] = amounts[i];
                    emit WithdrawFailed(
                        msg.sender,
                        token,
                        amounts[i],
                        "Transfer returned false"
                    );
                }
            } catch Error(string memory reason) {
                // If transfer throws an error, restore balance
                bank.balances[token] = amounts[i];
                emit WithdrawFailed(msg.sender, token, amounts[i], reason);
            } catch {
                // If transfer throws an error (no error message), restore balance
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
    function removeToken(address token) external nonReentrant {
        PiggyBank storage bank = piggyBanks[msg.sender];
        require(bank.exists, "Please create a piggy bank first");

        uint256 amount = bank.balances[token];
        require(amount > 0, "No balance for this token");

        // Clear balance
        bank.balances[token] = 0;

        // Remove from user's token list
        address[] storage tokens = userTokens[msg.sender];
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == token) {
                tokens[i] = tokens[tokens.length - 1];
                tokens.pop();
                break;
            }
        }

        emit TokenRemoved(msg.sender, token, amount);
    }

    /// @notice Get the balance information of all tokens for a user
    /// @param user User address
    /// @return tokens Array of token addresses
    /// @return balances Corresponding array of balances
    function getBalances(
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
