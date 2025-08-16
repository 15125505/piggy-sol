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
 * @title ScallionManor - Inheritance-based WBTC Savings Contract
 * @dev Implements an inheritance-based time-locked savings system with WBTC
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

/// @title Scallion Manor - Inheritance-based WBTC Savings Contract
/// @author zhoufeng
/// @notice Users can purchase manor access, lock WBTC with inheritance features
contract ScallionManor is Ownable, ReentrancyGuard {
    
    /// @dev Manor struct for each user
    struct Manor {
        bool hasAccess;           // Whether user has purchased manor access
        uint256 wbtcBalance;      // WBTC balance in the manor
        uint256 createdAt;        // When the manor was first funded
        uint256 lockPeriod;       // Lock period in seconds
        uint256 lastActiveTime;   // Last activity timestamp
        uint256 lastInheritorChange; // Last time inheritors were modified
        address[] inheritors;     // List of inheritors (max 10)
        bool exists;             // Whether manor exists
    }

    /// @dev Mapping of user address to their manor
    mapping(address => Manor) public manors;
    
    /// @dev Manor access price
    uint256 public manorAccessPrice;
    
    /// @dev Force change fee for inheritors
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
    
    /// @dev Permit2 canonical address (same on all chains)
    IPermit2 public constant permit2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    // Events
    event ManorAccessPurchased(address indexed user, uint256 price);
    event WBTCDeposited(address indexed user, uint256 amount, uint256 newBalance, uint256 lockPeriod);
    event WBTCWithdrawn(address indexed user, uint256 amount, address indexed withdrawer);
    event InheritorsUpdated(address indexed user, address[] newInheritors);
    event ActivityUpdated(address indexed user, uint256 timestamp);
    event ManorAccessPriceUpdated(uint256 newPrice);
    event ForceChangeFeeUpdated(uint256 newFee);
    event FallbackAddressUpdated(address newFallbackAddress);

    constructor(
        address _wbtcToken,
        uint256 _manorAccessPrice,
        uint256 _forceChangeFee,
        address _fallbackAddress
    ) Ownable(msg.sender) {
        require(_wbtcToken != address(0), "Invalid WBTC address");
        require(_fallbackAddress != address(0), "Invalid fallback address");
        
        wbtcToken = IERC20(_wbtcToken);
        manorAccessPrice = _manorAccessPrice;
        forceChangeFee = _forceChangeFee;
        fallbackAddress = _fallbackAddress;
    }

    /// @notice Purchase manor access
    function purchaseManorAccess() external payable nonReentrant {
        require(msg.value >= manorAccessPrice, "Insufficient payment for manor access");
        require(!manors[msg.sender].hasAccess, "Already has manor access");
        
        manors[msg.sender].hasAccess = true;
        manors[msg.sender].lastActiveTime = block.timestamp;
        manors[msg.sender].exists = true;
        
        emit ManorAccessPurchased(msg.sender, msg.value);
        emit ActivityUpdated(msg.sender, block.timestamp);
    }

    /// @notice Deposit WBTC using Permit2
    /// @param lockPeriod Lock period in seconds (only for first deposit)
    /// @param amount Amount of WBTC to deposit
    /// @param permit Permit2 permission struct
    /// @param signature Permit2 signature
    function depositWBTC(
        uint256 lockPeriod,
        uint256 amount,
        IPermit2.PermitTransferFrom calldata permit,
        bytes calldata signature
    ) external nonReentrant {
        require(manors[msg.sender].hasAccess, "Must purchase manor access first");
        require(amount > 0, "Deposit amount must be greater than 0");
        require(permit.permitted.token == address(wbtcToken), "Must deposit WBTC");
        
        Manor storage manor = manors[msg.sender];
        
        // If no balance and not locked, allow setting new lock period
        if (manor.wbtcBalance == 0 && 
            (manor.createdAt == 0 || block.timestamp >= manor.createdAt + manor.lockPeriod)) {
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
    /// @param forceChange Whether to pay fee for immediate change
    function setInheritors(address[] calldata newInheritors, bool forceChange) external payable nonReentrant {
        require(manors[msg.sender].hasAccess, "Must have manor access");
        require(newInheritors.length <= MAX_INHERITORS, "Too many inheritors");
        
        Manor storage manor = manors[msg.sender];
        
        // Check cooldown period
        if (manor.lastInheritorChange > 0 && 
            block.timestamp < manor.lastInheritorChange + INHERITOR_CHANGE_COOLDOWN) {
            if (forceChange) {
                require(msg.value >= forceChangeFee, "Insufficient fee for force change");
            } else {
                revert("Must wait for cooldown period or pay force change fee");
            }
        }
        
        // Validate that all inheritors have manor access
        for (uint256 i = 0; i < newInheritors.length; i++) {
            require(manors[newInheritors[i]].hasAccess, "Inheritor must have manor access");
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
    /// @param forceChange Whether to pay fee for immediate change
    function maintainInheritors(
        address manorOwner, 
        address[] calldata newInheritors, 
        bool forceChange
    ) external payable nonReentrant {
        address withdrawer = getWithdrawer(manorOwner);
        require(withdrawer == msg.sender, "You are not authorized to maintain");
        
        Manor storage manor = manors[manorOwner];
        
        // Check cooldown period
        if (manor.lastInheritorChange > 0 && 
            block.timestamp < manor.lastInheritorChange + INHERITOR_CHANGE_COOLDOWN) {
            if (forceChange) {
                require(msg.value >= forceChangeFee, "Insufficient fee for force change");
            } else {
                revert("Must wait for cooldown period or pay force change fee");
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
            require(manors[newInheritors[i]].hasAccess, "Inheritor must have manor access");
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
        
        if (!manor.exists || manor.wbtcBalance == 0) {
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
            manor.hasAccess,
            manor.wbtcBalance,
            manor.createdAt + manor.lockPeriod,
            manor.lastActiveTime,
            manor.inheritors
        );
    }

    // Owner functions
    
    /// @notice Update manor access price
    /// @param newPrice New price in wei
    function setManorAccessPrice(uint256 newPrice) external onlyOwner {
        manorAccessPrice = newPrice;
        emit ManorAccessPriceUpdated(newPrice);
    }

    /// @notice Update force change fee
    /// @param newFee New fee in wei
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

    /// @notice Withdraw contract's ETH balance
    function withdrawETH() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No ETH to withdraw");
        payable(owner()).transfer(balance);
    }

    /// @notice Emergency function to recover stuck tokens
    /// @param token Token address to recover
    /// @param amount Amount to recover
    function emergencyRecoverToken(address token, uint256 amount) external onlyOwner {
        require(token != address(wbtcToken), "Cannot recover WBTC");
        IERC20(token).transfer(owner(), amount);
    }
}