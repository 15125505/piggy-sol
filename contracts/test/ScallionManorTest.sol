// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

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

contract ScallionManorTest is Ownable, ReentrancyGuard {

    struct Manor {
        uint256 wbtcBalance;         // WBTC余额
        uint256 createdAt;           // 创建时间（0=无权限，1=有权限未存入，>1=存入时间）
        uint256 lockPeriod;          // 锁定期（秒）
        uint256 lastActiveTime;      // 最后活跃时间
        uint256 lastInheritorChange; // 最后继承人修改时间
        address[] inheritors;        // 继承人列表（最多10人）
    }

    mapping(address => Manor) public manors;

    uint256 public manorAccessPrice;     // 庄园访问价格（WLD）
    uint256 public forceChangeFee;       // 强制修改费用（WLD）

    uint256 public constant INACTIVE_THRESHOLD = 365 days;           // 不活跃阈值
    uint256 public constant INHERITOR_CHANGE_COOLDOWN = 30 days;     // 继承人修改冷却期
    uint256 public constant MAX_INHERITORS = 10;                     // 最大继承人数

    address public fallbackAddress;      // 兜底地址
    IERC20 public immutable wbtcToken;   // WBTC代币合约
    IERC20 public immutable wldToken;    // WLD代币合约
    IPermit2 public immutable permit2;   // 可配置的Permit2地址

    // 事件
    event ManorAccessPurchased(address indexed user, uint256 wldAmount);
    event WBTCDeposited(address indexed user, uint256 amount, uint256 newBalance, uint256 lockPeriod);
    event WBTCWithdrawn(address indexed user, uint256 amount, address indexed withdrawer);
    event InheritorsUpdated(address indexed user, address[] newInheritors);
    event ActivityUpdated(address indexed user, uint256 timestamp);
    event ManorAccessPriceUpdated(uint256 newPrice);
    event ForceChangeFeeUpdated(uint256 newFee);
    event FallbackAddressUpdated(address newFallbackAddress);
    event DeveloperTipped(address indexed tipper, uint256 wldAmount, string message);

    constructor(
        address _wbtcToken,
        address _wldToken,
        address _permit2Address,
        uint256 _manorAccessPrice,
        uint256 _forceChangeFee,
        address _fallbackAddress
    ) Ownable(msg.sender) {
        require(_wbtcToken != address(0), "Invalid WBTC address");
        require(_wldToken != address(0), "Invalid WLD address");
        require(_permit2Address != address(0), "Invalid Permit2 address");
        require(_fallbackAddress != address(0), "Invalid fallback address");

        wbtcToken = IERC20(_wbtcToken);
        wldToken = IERC20(_wldToken);
        permit2 = IPermit2(_permit2Address);
        manorAccessPrice = _manorAccessPrice;
        forceChangeFee = _forceChangeFee;
        fallbackAddress = _fallbackAddress;
    }

    /**
     * @dev 检查用户是否拥有庄园权限
     */
    function hasManorAccess(address user) public view returns (bool) {
        return manors[user].createdAt > 0;
    }

    /**
     * @dev 购买庄园权限
     * @param permit Permit2许可证（金额必须 == manorAccessPrice）
     * @param signature Permit2签名
     */
    function purchaseManorAccess(
        IPermit2.PermitTransferFrom calldata permit,
        bytes calldata signature
    ) external nonReentrant {
        require(!hasManorAccess(msg.sender), "Already has manor access");
        require(permit.permitted.token == address(wldToken), "Must pay with WLD");
        require(permit.permitted.amount == manorAccessPrice, "Must pay exact manor access price");

        permit2.permitTransferFrom(
            permit,
            IPermit2.SignatureTransferDetails({
                to: address(this),
                requestedAmount: permit.permitted.amount
            }),
            msg.sender,
            signature
        );

        // 初始化庄园权限并设置活跃时间
        manors[msg.sender].createdAt = 1;
        manors[msg.sender].lastActiveTime = block.timestamp;

        emit ManorAccessPurchased(msg.sender, permit.permitted.amount);
        emit ActivityUpdated(msg.sender, block.timestamp);
    }

    /**
     * @dev 存入WBTC
     * @param lockPeriod 锁定期（秒，仅首次存入时有效）
     * @param permit Permit2许可证（必须是WBTC代币）
     * @param signature Permit2签名
     */
    function depositWBTC(
        uint256 lockPeriod,
        IPermit2.PermitTransferFrom calldata permit,
        bytes calldata signature
    ) external nonReentrant {
        require(hasManorAccess(msg.sender), "Must purchase manor access first");
        require(permit.permitted.token == address(wbtcToken), "Must deposit WBTC");
        require(permit.permitted.amount > 0, "Deposit amount must be greater than 0");

        Manor storage manor = manors[msg.sender];

        // 如果没有余额且（首次或锁定期已过期），可以设置新锁定期
        if (manor.wbtcBalance == 0 &&
            (manor.createdAt <= 1 || block.timestamp >= manor.createdAt + manor.lockPeriod)) {
            require(lockPeriod > 0, "Lock period must be greater than 0");
            manor.createdAt = block.timestamp;
            manor.lockPeriod = lockPeriod;
        }

        permit2.permitTransferFrom(
            permit,
            IPermit2.SignatureTransferDetails({
                to: address(this),
                requestedAmount: permit.permitted.amount
            }),
            msg.sender,
            signature
        );

        manor.wbtcBalance += permit.permitted.amount;
        manor.lastActiveTime = block.timestamp;

        emit WBTCDeposited(msg.sender, permit.permitted.amount, manor.wbtcBalance, manor.lockPeriod);
        emit ActivityUpdated(msg.sender, block.timestamp);
    }

    /**
     * @dev 提取自己的WBTC
     */
    function withdrawWBTC() external nonReentrant {
        Manor storage manor = manors[msg.sender];
        require(manor.wbtcBalance > 0, "No WBTC to withdraw");
        require(block.timestamp >= manor.createdAt + manor.lockPeriod, "Still locked");

        // 先更新活跃时间，确保getWithdrawer能正确识别当前用户
        manor.lastActiveTime = block.timestamp;
        
        address withdrawer = getWithdrawer(msg.sender);
        require(withdrawer != address(0), "No valid withdrawer found");
        require(withdrawer == msg.sender, "You are not authorized to withdraw");

        uint256 amount = manor.wbtcBalance;
        manor.wbtcBalance = 0;

        require(wbtcToken.transfer(msg.sender, amount), "Transfer failed");

        emit WBTCWithdrawn(msg.sender, amount, msg.sender);
        emit ActivityUpdated(msg.sender, block.timestamp);
    }

    /**
     * @dev 刷新用户活跃时间
     */
    function refreshActivity() external nonReentrant {
        require(hasManorAccess(msg.sender), "Must have manor access");
        
        manors[msg.sender].lastActiveTime = block.timestamp;
        
        emit ActivityUpdated(msg.sender, block.timestamp);
    }

    /**
     * @dev 打赏开发者
     * @param permit Permit2许可证（必须是WLD代币）
     * @param signature Permit2签名
     * @param message 打赏消息（支持中文）
     */
    function tipDeveloper(
        IPermit2.PermitTransferFrom calldata permit,
        bytes calldata signature,
        string calldata message
    ) external nonReentrant {
        require(permit.permitted.token == address(wldToken), "Must tip with WLD");
        require(permit.permitted.amount > 0, "Tip amount must be greater than 0");

        permit2.permitTransferFrom(
            permit,
            IPermit2.SignatureTransferDetails({
                to: address(this),
                requestedAmount: permit.permitted.amount
            }),
            msg.sender,
            signature
        );

        // 如果用户有庄园权限，更新活跃时间
        if (hasManorAccess(msg.sender)) {
            manors[msg.sender].lastActiveTime = block.timestamp;
            emit ActivityUpdated(msg.sender, block.timestamp);
        }

        emit DeveloperTipped(msg.sender, permit.permitted.amount, message);
    }

    /**
     * @dev 获取当前有权提取的地址
     */
    function getWithdrawer(address manorOwner) public view returns (address) {
        Manor storage manor = manors[manorOwner];

        if (!hasManorAccess(manorOwner) || manor.wbtcBalance == 0) {
            return address(0);
        }

        // 检查庄园主人是否活跃
        if (block.timestamp <= manor.lastActiveTime + INACTIVE_THRESHOLD) {
            return manorOwner;
        }

        // 检查继承人是否活跃
        for (uint256 i = 0; i < manor.inheritors.length; i++) {
            address inheritor = manor.inheritors[i];
            if (manors[inheritor].lastActiveTime + INACTIVE_THRESHOLD >= block.timestamp) {
                return inheritor;
            }
        }

        // 所有人都不活跃，返回兜底地址
        return fallbackAddress;
    }

    /**
     * @dev 获取庄园信息
     */
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

    // === Owner管理函数 ===

    function withdrawWLD() external onlyOwner {
        uint256 balance = wldToken.balanceOf(address(this));
        require(balance > 0, "No WLD to withdraw");
        require(wldToken.transfer(owner(), balance), "Transfer failed");
    }
}