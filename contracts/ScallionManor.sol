// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * ███████╗ ██████╗ █████╗ ██╗     ██╗     ██╗ ██████╗ ███╗   ██╗    ███╗   ███╗ █████╗ ███╗   ██╗ ██████╗ ██████╗
 * ██╔════╝██╔════╝██╔══██╗██║     ██║     ██║██╔═══██╗████╗  ██║    ████╗ ████║██╔══██╗████╗  ██║██╔═══██╗██╔══██╗
 * ███████╗██║     ███████║██║     ██║     ██║██║   ██║██╔██╗ ██║    ██╔████╔██║███████║██╔██╗ ██║██║   ██║██████╔╝
 * ╚════██║██║     ██╔══██║██║     ██║     ██║██║   ██║██║╚██╗██║    ██║╚██╔╝██║██╔══██║██║╚██╗██║██║   ██║██╔══██╗
 * ███████║╚██████╗██║  ██║███████╗███████╗██║╚██████╔╝██║ ╚████║    ██║ ╚═╝ ██║██║  ██║██║ ╚████║╚██████╔╝██║  ██║
 * ╚══════╝ ╚═════╝╚═╝  ╚═╝╚══════╝╚══════╝╚═╝ ╚═════╝ ╚═╝  ╚═══╝    ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝ ╚═════╝ ╚═╝  ╚═╝
 *
 * @title ScallionManor - Optimized Inheritance-based WBTC Savings Contract
 * @dev Implements an inheritance-based time-locked savings system with WBTC and WLD fee payments
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

/// @title Scallion Manor - Optimized Inheritance-based WBTC Savings Contract
/// @author zhoufeng
/// @notice Users pay WLD to access manor, lock WBTC with inheritance features
contract ScallionManorOptimized is Ownable, ReentrancyGuard {

    /// @dev Optimized Manor struct for each user
    struct Manor {
        uint256 wbtcBalance;         // WBTC balance in the manor
        uint256 createdAt;           // When the manor was first funded (0 = no access)
        uint256 lockPeriod;          // Lock period in seconds
        uint256 lastActiveTime;      // Last activity timestamp
        uint256 lastInheritorChange; // Last time inheritors were modified
        address[] inheritors;        // List of inheritors (max 10)
    }

    /// @dev Mapping of user address to their manor
    mapping(address => Manor) public manors;

    /// @dev Manor access price in WLD tokens
    uint256 public manorAccessPrice;

    /// @dev Force change fee for inheritors in WLD tokens
    uint256 public forceChangeFee;

    /// @dev Inactive threshold (default 1 year)
    uint256 public constant INACTIVE_THRESHOLD = 365 days;

    /// @dev Inheritor change cooldown (30 days)
    uint256 public constant INHERITOR_CHANGE_COOLDOWN = 30 days;

    /// @dev Maximum number of inheritors
    uint256 public constant MAX_INHERITORS = 10;

    /// @dev Fallback address for unclaimed funds
    address public fallbackAddress;

    /// @dev WBTC token contract
    IERC20 public immutable wbtcToken;

    /// @dev WLD token contract for fee payments
    IERC20 public immutable wldToken;

    /// @dev Permit2 canonical address (same on all chains)
    IPermit2 public constant permit2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    // Events
    event ManorAccessPurchased(address indexed user, uint256 wldAmount);
    event WBTCDeposited(address indexed user, uint256 amount, uint256 newBalance, uint256 lockPeriod);
    event WBTCWithdrawn(address indexed user, uint256 amount, address indexed withdrawer);
    event InheritorsUpdated(address indexed user, address[] newInheritors);
    event ActivityUpdated(address indexed user, uint256 timestamp);
    event ManorAccessPriceUpdated(uint256 newPrice);
    event ForceChangeFeeUpdated(uint256 newFee);
    event FallbackAddressUpdated(address newFallbackAddress);

    constructor(
        address _wbtcToken,
        address _wldToken,
        uint256 _manorAccessPrice,
        uint256 _forceChangeFee,
        address _fallbackAddress
    ) Ownable(msg.sender) {
        require(_wbtcToken != address(0), "Invalid WBTC address");
        require(_wldToken != address(0), "Invalid WLD address");
        require(_fallbackAddress != address(0), "Invalid fallback address");

        wbtcToken = IERC20(_wbtcToken);
        wldToken = IERC20(_wldToken);
        manorAccessPrice = _manorAccessPrice;
        forceChangeFee = _forceChangeFee;
        fallbackAddress = _fallbackAddress;
    }

    /// @notice Check if user has manor access
    /// @param user User address to check
    /// @return True if user has access
    function hasManorAccess(address user) public view returns (bool) {
        return manors[user].createdAt > 0;
    }

    /// @notice Purchase manor access with WLD tokens
    /// @param wldAmount Amount of WLD to pay (must be >= manorAccessPrice)
    /// @param permit Permit2 permission struct for WLD
    /// @param signature Permit2 signature
    function purchaseManorAccess(
        uint256 wldAmount,
        IPermit2.PermitTransferFrom calldata permit,
        bytes calldata signature
    ) external nonReentrant {
        require(wldAmount >= manorAccessPrice, "Insufficient WLD payment");
        require(!hasManorAccess(msg.sender), "Already has manor access");
        require(permit.permitted.token == address(wldToken), "Must pay with WLD");

        // Transfer WLD via Permit2
        permit2.permitTransferFrom(
            permit,
            IPermit2.SignatureTransferDetails({
                to: address(this),
                requestedAmount: wldAmount
            }),
            msg.sender,
            signature
        );

        // Initialize manor with access granted
        manors[msg.sender].createdAt = 1; // Non-zero indicates access
        manors[msg.sender].lastActiveTime = block.timestamp;

        emit ManorAccessPurchased(msg.sender, wldAmount);
        emit ActivityUpdated(msg.sender, block.timestamp);
    }

    /// @notice Deposit WBTC using Permit2
    /// @param lockPeriod Lock period in seconds (only for first deposit)
    /// @param amount Amount of WBTC to deposit
    /// @param permit Permit2 permission struct for WBTC
    /// @param signature Permit2 signature
    function depositWBTC(
        uint256 lockPeriod,
        uint256 amount,
        IPermit2.PermitTransferFrom calldata permit,
        bytes calldata signature
    ) external nonReentrant {
        require(hasManorAccess(msg.sender), "Must purchase manor access first");
        require(amount > 0, "Deposit amount must be greater than 0");
        require(permit.permitted.token == address(wbtcToken), "Must deposit WBTC");

        Manor storage manor = manors[msg.sender];

        // If no balance and not locked, allow setting new lock period
        if (manor.wbtcBalance == 0 &&
            (manor.createdAt <= 1 || block.timestamp >= manor.createdAt + manor.lockPeriod)) {
            require(lockPeriod > 0, "Lock period must be greater than 0");
            manor.createdAt = block.timestamp;
            manor.lockPeriod = lockPeriod;
        }

        // Transfer WBTC via Permit2
        permit2.permitTransferFrom(
            permit,
            IPermit2.SignatureTransferDetails({
                to: address(this),
                requestedAmount: amount
            }),
            msg.sender,
            signature
        );

        manor.wbtcBalance += amount;
        manor.lastActiveTime = block.timestamp;

        emit WBTCDeposited(msg.sender, amount, manor.wbtcBalance, manor.lockPeriod);
        emit ActivityUpdated(msg.sender, block.timestamp);
    }

    /// @notice Set inheritors (max 10)
    /// @param newInheritors Array of inheritor addresses
    /// @param forceChange Whether to pay WLD fee for immediate change
    /// @param wldAmount Amount of WLD to pay if force change (ignored if forceChange is false)
    /// @param permit Permit2 permission struct for WLD (only if forceChange is true)
    /// @param signature Permit2 signature (only if forceChange is true)
    function setInheritors(
        address[] calldata newInheritors,
        bool forceChange,
        uint256 wldAmount,
        IPermit2.PermitTransferFrom calldata permit,
        bytes calldata signature
    ) external nonReentrant {
        require(hasManorAccess(msg.sender), "Must have manor access");
        require(newInheritors.length <= MAX_INHERITORS, "Too many inheritors");

        Manor storage manor = manors[msg.sender];

        // Check cooldown period
        if (manor.lastInheritorChange > 0 &&
            block.timestamp < manor.lastInheritorChange + INHERITOR_CHANGE_COOLDOWN) {
            if (forceChange) {
                require(wldAmount >= forceChangeFee, "Insufficient WLD for force change");
                require(permit.permitted.token == address(wldToken), "Must pay with WLD");

                // Transfer WLD fee via Permit2
                permit2.permitTransferFrom(
                    permit,
                    IPermit2.SignatureTransferDetails({
                        to: address(this),
                        requestedAmount: wldAmount
                    }),
                    msg.sender,
                    signature
                );
            } else {
                revert("Must wait for cooldown period or pay WLD force change fee");
            }
        }

        // Validate that all inheritors have manor access
        for (uint256 i = 0; i < newInheritors.length; i++) {
            require(hasManorAccess(newInheritors[i]), "Inheritor must have manor access");
            // Check for duplicates
            for (uint256 j = i + 1; j < newInheritors.length; j++) {
                require(newInheritors[i] != newInheritors[j], "Duplicate inheritors not allowed");
            }
        }

        manor.inheritors = newInheritors;
        manor.lastInheritorChange = block.timestamp;
        manor.lastActiveTime = block.timestamp;

        emit InheritorsUpdated(msg.sender, newInheritors);
        emit ActivityUpdated(msg.sender, block.timestamp);
    }

    /// @notice Withdraw WBTC (only available after lock period)
    function withdrawWBTC() external nonReentrant {
        address withdrawer = getWithdrawer(msg.sender);
        require(withdrawer != address(0), "No valid withdrawer found");
        require(withdrawer == msg.sender, "You are not authorized to withdraw");

        Manor storage manor = manors[msg.sender];
        require(manor.wbtcBalance > 0, "No WBTC to withdraw");
        require(block.timestamp >= manor.createdAt + manor.lockPeriod, "Still locked");

        uint256 amount = manor.wbtcBalance;
        manor.wbtcBalance = 0;

        require(wbtcToken.transfer(msg.sender, amount), "Transfer failed");

        emit WBTCWithdrawn(msg.sender, amount, msg.sender);
    }

    /// @notice Inherit WBTC from another user's manor
    /// @param manorOwner The manor owner whose WBTC to inherit
    function inheritWBTC(address manorOwner) external nonReentrant {
        address withdrawer = getWithdrawer(manorOwner);
        require(withdrawer == msg.sender, "You are not authorized to inherit");

        Manor storage manor = manors[manorOwner];
        require(manor.wbtcBalance > 0, "No WBTC to inherit");
        require(block.timestamp >= manor.createdAt + manor.lockPeriod, "Still locked");

        uint256 amount = manor.wbtcBalance;
        manor.wbtcBalance = 0;

        require(wbtcToken.transfer(msg.sender, amount), "Transfer failed");

        emit WBTCWithdrawn(manorOwner, amount, msg.sender);
    }

    /// @notice Maintain inheritors list (only for current withdrawer)
    /// @param manorOwner The manor owner whose inheritors to maintain
    /// @param newInheritors New inheritors list (can only modify after current position)
    /// @param forceChange Whether to pay WLD fee for immediate change
    /// @param wldAmount Amount of WLD to pay if force change
    /// @param permit Permit2 permission struct for WLD (only if forceChange is true)
    /// @param signature Permit2 signature (only if forceChange is true)
    function maintainInheritors(
        address manorOwner,
        address[] calldata newInheritors,
        bool forceChange,
        uint256 wldAmount,
        IPermit2.PermitTransferFrom calldata permit,
        bytes calldata signature
    ) external nonReentrant {
        address withdrawer = getWithdrawer(manorOwner);
        require(withdrawer == msg.sender, "You are not authorized to maintain");

        Manor storage manor = manors[manorOwner];

        // Check cooldown period
        if (manor.lastInheritorChange > 0 &&
            block.timestamp < manor.lastInheritorChange + INHERITOR_CHANGE_COOLDOWN) {
            if (forceChange) {
                require(wldAmount >= forceChangeFee, "Insufficient WLD for force change");
                require(permit.permitted.token == address(wldToken), "Must pay with WLD");

                // Transfer WLD fee via Permit2
                permit2.permitTransferFrom(
                    permit,
                    IPermit2.SignatureTransferDetails({
                        to: address(this),
                        requestedAmount: wldAmount
                    }),
                    msg.sender,
                    signature
                );
            } else {
                revert("Must wait for cooldown period or pay WLD force change fee");
            }
        }

        // Find current withdrawer position in inheritors list
        uint256 withdrawerIndex = type(uint256).max;
        for (uint256 i = 0; i < manor.inheritors.length; i++) {
            if (manor.inheritors[i] == msg.sender) {
                withdrawerIndex = i;
                break;
            }
        }

        // Validate new inheritors list
        require(newInheritors.length <= MAX_INHERITORS, "Too many inheritors");

        // Ensure inheritors before withdrawer position remain unchanged
        if (withdrawerIndex != type(uint256).max) {
            require(newInheritors.length > withdrawerIndex, "Must include all previous inheritors");
            for (uint256 i = 0; i <= withdrawerIndex; i++) {
                require(newInheritors[i] == manor.inheritors[i], "Cannot modify previous inheritors");
            }
        }

        // Validate all new inheritors have manor access
        for (uint256 i = 0; i < newInheritors.length; i++) {
            require(hasManorAccess(newInheritors[i]), "Inheritor must have manor access");
        }

        manor.inheritors = newInheritors;
        manor.lastInheritorChange = block.timestamp;

        emit InheritorsUpdated(manorOwner, newInheritors);
    }

    /// @notice Get the current withdrawer for a manor
    /// @param manorOwner The manor owner
    /// @return The address authorized to withdraw, or address(0) if none
    function getWithdrawer(address manorOwner) public view returns (address) {
        Manor storage manor = manors[manorOwner];

        if (!hasManorAccess(manorOwner) || manor.wbtcBalance == 0) {
            return address(0);
        }

        // Check if manor owner is active
        if (block.timestamp <= manor.lastActiveTime + INACTIVE_THRESHOLD) {
            return manorOwner;
        }

        // Check inheritors in order
        for (uint256 i = 0; i < manor.inheritors.length; i++) {
            address inheritor = manor.inheritors[i];
            if (manors[inheritor].lastActiveTime + INACTIVE_THRESHOLD >= block.timestamp) {
                return inheritor;
            }
        }

        // Return fallback address if no one is active
        return fallbackAddress;
    }

    /// @notice Check if a user is active
    /// @param user User address to check
    /// @return True if user is active
    function isUserActive(address user) external view returns (bool) {
        return block.timestamp <= manors[user].lastActiveTime + INACTIVE_THRESHOLD;
    }

    /// @notice Get manor information
    /// @param user User address
    /// @return hasAccess Whether user has manor access
    /// @return wbtcBalance WBTC balance
    /// @return unlockTime When funds can be withdrawn
    /// @return lastActiveTime Last activity time
    /// @return inheritors List of inheritors
    function getManorInfo(address user) external view returns (
        bool hasAccess,
        uint256 wbtcBalance,
        uint256 unlockTime,
        uint256 lastActiveTime,
        address[] memory inheritors
    ) {
        Manor storage manor = manors[user];
        return (
            hasManorAccess(user),
            manor.wbtcBalance,
            manor.createdAt > 1 ? manor.createdAt + manor.lockPeriod : 0,
            manor.lastActiveTime,
            manor.inheritors
        );
    }

    // Owner functions

    /// @notice Update manor access price
    /// @param newPrice New price in WLD tokens
    function setManorAccessPrice(uint256 newPrice) external onlyOwner {
        manorAccessPrice = newPrice;
        emit ManorAccessPriceUpdated(newPrice);
    }

    /// @notice Update force change fee
    /// @param newFee New fee in WLD tokens
    function setForceChangeFee(uint256 newFee) external onlyOwner {
        forceChangeFee = newFee;
        emit ForceChangeFeeUpdated(newFee);
    }

    /// @notice Update fallback address
    /// @param newFallbackAddress New fallback address
    function setFallbackAddress(address newFallbackAddress) external onlyOwner {
        require(newFallbackAddress != address(0), "Invalid fallback address");
        fallbackAddress = newFallbackAddress;
        emit FallbackAddressUpdated(newFallbackAddress);
    }

    /// @notice Withdraw collected WLD fees
    function withdrawWLD() external onlyOwner {
        uint256 balance = wldToken.balanceOf(address(this));
        require(balance > 0, "No WLD to withdraw");
        require(wldToken.transfer(owner(), balance), "Transfer failed");
    }

    /// @notice Emergency function to recover stuck tokens
    /// @param token Token address to recover
    /// @param amount Amount to recover
    function emergencyRecoverToken(address token, uint256 amount) external onlyOwner {
        require(token != address(wbtcToken), "Cannot recover WBTC");
        require(token != address(wldToken), "Cannot recover WLD");
        IERC20(token).transfer(owner(), amount);
    }
}
