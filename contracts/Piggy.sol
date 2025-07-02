// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IERC20.sol";

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

/// @title Multi-user ERC20 Piggy Bank Contract (WLD + Permit2)
/// @author zhoufeng
/// @notice Users can create their own piggy bank, and can only withdraw the full balance after a fixed period. Deposits are made in WLD (ERC20).
contract Piggy {
    /// @dev Piggy bank struct
    struct PiggyBank {
        uint256 createdAt;
        uint256 balance; // Balance in WLD
        bool exists;
        uint256 lockPeriod;
    }

    /// @dev Mapping to record each user's piggy bank
    mapping(address => PiggyBank) public piggyBanks;

    event PiggyBankCreated(address indexed user, uint256 createdAt);
    event Deposited(address indexed user, uint256 amount, uint256 newBalance);
    event Withdrawn(address indexed user, uint256 amount);

    IERC20 public immutable wldToken;
    IPermit2 public immutable permit2;
    address public constant PERMIT2_ADDRESS = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    /// @param _wldToken The address of the WLD ERC20 token
    constructor(address _wldToken) {
        require(_wldToken != address(0), "Invalid WLD address");
        wldToken = IERC20(_wldToken);
        permit2 = IPermit2(PERMIT2_ADDRESS);
    }

    /// @notice Query the balance of a user's piggy bank
    function getBalance(address user) external view returns (uint256) {
        return piggyBanks[user].balance;
    }

    /// @notice Query the unlock timestamp of a user's piggy bank
    /// @param user The user's address
    /// @return The unlock timestamp (in seconds)
    function getUnlockTimestamp(address user) external view returns (uint256) {
        PiggyBank storage bank = piggyBanks[user];
        require(bank.exists, "Piggy bank does not exist");
        return bank.createdAt + bank.lockPeriod;
    }

    /// @notice Deposit WLD (first deposit automatically creates a piggy bank, uses Permit2 to transfer WLD)
    /// @param lockPeriod Lock period (in seconds), only effective when creating for the first time
    /// @param amount Amount of WLD to deposit
    /// @param permit Permit2 permission struct
    /// @param signature Permit2 signature
    function deposit(
        uint256 lockPeriod,
        uint256 amount,
        IPermit2.PermitTransferFrom calldata permit,
        bytes calldata signature
    ) external {
        require(amount > 0, "Deposit amount must be greater than 0");
        PiggyBank storage bank = piggyBanks[msg.sender];
        if (!bank.exists) {
            require(lockPeriod > 0, "Lock period must be greater than 0");
            piggyBanks[msg.sender] = PiggyBank({
                createdAt: block.timestamp,
                balance: 0,
                exists: true,
                lockPeriod: lockPeriod
            });
            emit PiggyBankCreated(msg.sender, block.timestamp);
        }
        // If balance is 0 and lock period has expired, reset creation time
        if (
            bank.balance == 0 &&
            block.timestamp >= bank.createdAt + bank.lockPeriod
        ) {
            bank.createdAt = block.timestamp;
            bank.lockPeriod = lockPeriod;
        }
        // Permit2 transfer WLD
        permit2.permitTransferFrom(
            permit,
            IPermit2.SignatureTransferDetails({
                to: address(this),
                requestedAmount: amount
            }),
            msg.sender,
            signature
        );
        bank.balance += amount;
        emit Deposited(msg.sender, amount, bank.balance);
    }

    /// @notice Withdraw (can only withdraw the full balance after the lock period, transfers WLD)
    function withdraw() external {
        PiggyBank storage bank = piggyBanks[msg.sender];
        require(bank.exists, "Please create a piggy bank first");
        require(block.timestamp >= bank.createdAt + bank.lockPeriod, "Not yet unlocked");
        uint256 amount = bank.balance;
        require(amount > 0, "No balance to withdraw");
        require(wldToken.transfer(msg.sender, amount), "Transfer failed");
        bank.balance = 0;
        emit Withdrawn(msg.sender, amount);
    }
} 