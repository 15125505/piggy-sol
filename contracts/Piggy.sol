// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

interface IERC20 {
    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /**
     * @dev Returns the value of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the value of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves a `value` amount of tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 value) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets a `value` amount of tokens as the allowance of `spender` over the
     * caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 value) external returns (bool);

    /**
     * @dev Moves a `value` amount of tokens from `from` to `to` using the
     * allowance mechanism. `value` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}


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