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
 * @title ScallionManor -  Inheritance-based WBTC Savings Contract
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

contract ScallionManor is Ownable, ReentrancyGuard {

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
    IPermit2 public constant permit2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    // 事件
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
     * @dev 设置继承人
     */
    function setInheritors(
        address[] calldata newInheritors,
        bool forceChange,
        IPermit2.PermitTransferFrom calldata permit,
        bytes calldata signature
    ) external nonReentrant {
        require(hasManorAccess(msg.sender), "Must have manor access");
        require(newInheritors.length <= MAX_INHERITORS, "Too many inheritors");

        Manor storage manor = manors[msg.sender];

        // 检查冷却期
        if (manor.lastInheritorChange > 0 &&
            block.timestamp < manor.lastInheritorChange + INHERITOR_CHANGE_COOLDOWN) {
            if (forceChange) {
                require(permit.permitted.token == address(wldToken), "Must pay with WLD");
                require(permit.permitted.amount == forceChangeFee, "Must pay exact force change fee");

                permit2.permitTransferFrom(
                    permit,
                    IPermit2.SignatureTransferDetails({
                        to: address(this),
                        requestedAmount: permit.permitted.amount
                    }),
                    msg.sender,
                    signature
                );
            } else {
                revert("Must wait for cooldown period or pay WLD force change fee");
            }
        }

        // 验证所有继承人都有庄园权限
        for (uint256 i = 0; i < newInheritors.length; i++) {
            require(hasManorAccess(newInheritors[i]), "Inheritor must have manor access");
            // 检查重复项
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
     * @dev 继承他人的WBTC
     */
    function inheritWBTC(address manorOwner) external nonReentrant {
        Manor storage manor = manors[manorOwner];
        require(manor.wbtcBalance > 0, "No WBTC to inherit");
        require(block.timestamp >= manor.createdAt + manor.lockPeriod, "Still locked");

        // 先更新继承人的活跃时间，确保getWithdrawer能正确识别继承人
        manors[msg.sender].lastActiveTime = block.timestamp;

        address withdrawer = getWithdrawer(manorOwner);
        require(withdrawer == msg.sender, "You are not authorized to inherit");

        uint256 amount = manor.wbtcBalance;
        manor.wbtcBalance = 0;

        require(wbtcToken.transfer(msg.sender, amount), "Transfer failed");

        emit WBTCWithdrawn(manorOwner, amount, msg.sender);
        emit ActivityUpdated(msg.sender, block.timestamp);
    }

    /**
     * @dev 维护继承人列表 - 严格费用匹配
     */
    function maintainInheritors(
        address manorOwner,
        address[] calldata newInheritors,
        bool forceChange,
        IPermit2.PermitTransferFrom calldata permit,
        bytes calldata signature
    ) external nonReentrant {
        // 先更新维护者的活跃时间，确保getWithdrawer能正确识别维护者
        manors[msg.sender].lastActiveTime = block.timestamp;

        address withdrawer = getWithdrawer(manorOwner);
        require(withdrawer == msg.sender, "You are not authorized to maintain");

        Manor storage manor = manors[manorOwner];

        // 检查冷却期
        if (manor.lastInheritorChange > 0 &&
            block.timestamp < manor.lastInheritorChange + INHERITOR_CHANGE_COOLDOWN) {
            if (forceChange) {
                require(permit.permitted.token == address(wldToken), "Must pay with WLD");
                require(permit.permitted.amount == forceChangeFee, "Must pay exact force change fee");

                permit2.permitTransferFrom(
                    permit,
                    IPermit2.SignatureTransferDetails({
                        to: address(this),
                        requestedAmount: permit.permitted.amount
                    }),
                    msg.sender,
                    signature
                );
            } else {
                revert("Must wait for cooldown period or pay WLD force change fee");
            }
        }

        // 找到当前维护者在继承人列表中的位置
        uint256 withdrawerIndex = type(uint256).max;
        for (uint256 i = 0; i < manor.inheritors.length; i++) {
            if (manor.inheritors[i] == msg.sender) {
                withdrawerIndex = i;
                break;
            }
        }

        require(newInheritors.length <= MAX_INHERITORS, "Too many inheritors");

        // 确保维护者位置之前的继承人保持不变
        if (withdrawerIndex != type(uint256).max) {
            require(newInheritors.length > withdrawerIndex, "Must include all previous inheritors");
            for (uint256 i = 0; i <= withdrawerIndex; i++) {
                require(newInheritors[i] == manor.inheritors[i], "Cannot modify previous inheritors");
            }
        }

        // 验证所有新继承人都有庄园权限
        for (uint256 i = 0; i < newInheritors.length; i++) {
            require(hasManorAccess(newInheritors[i]), "Inheritor must have manor access");
        }

        manor.inheritors = newInheritors;
        manor.lastInheritorChange = block.timestamp;

        emit InheritorsUpdated(manorOwner, newInheritors);
        emit ActivityUpdated(msg.sender, block.timestamp); // 维护者活跃时间更新
    }

    /**
     * @dev 获取当前有权提取的地址
     * 由于继承人必须拥有庄园权限，因此必然有活跃时间，无需特殊处理
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
        // ✅ 继承人必须有庄园权限，因此必然有lastActiveTime，无需特殊处理
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
     * @dev 检查用户是否活跃
     */
    function isUserActive(address user) external view returns (bool) {
        return block.timestamp <= manors[user].lastActiveTime + INACTIVE_THRESHOLD;
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

    /**
     * @dev 更新庄园价格（移除上限限制，因为使用严格匹配）
     */
    function setManorAccessPrice(uint256 newPrice) external onlyOwner {
        manorAccessPrice = newPrice;
        emit ManorAccessPriceUpdated(newPrice);
    }

    /**
     * @dev 更新强制修改费用（移除上限限制，因为使用严格匹配）
     */
    function setForceChangeFee(uint256 newFee) external onlyOwner {
        forceChangeFee = newFee;
        emit ForceChangeFeeUpdated(newFee);
    }

    /**
     * @dev 更新兜底地址
     */
    function setFallbackAddress(address newFallbackAddress) external onlyOwner {
        require(newFallbackAddress != address(0), "Invalid fallback address");
        fallbackAddress = newFallbackAddress;
        emit FallbackAddressUpdated(newFallbackAddress);
    }

    /**
     * @dev 提取收集的WLD费用
     */
    function withdrawWLD() external onlyOwner {
        uint256 balance = wldToken.balanceOf(address(this));
        require(balance > 0, "No WLD to withdraw");
        require(wldToken.transfer(owner(), balance), "Transfer failed");
    }

    /**
     * @dev 紧急恢复被误转的代币
     */
    function emergencyRecoverToken(address token, uint256 amount) external onlyOwner {
        require(token != address(wbtcToken), "Cannot recover WBTC");
        require(token != address(wldToken), "Cannot recover WLD");
        require(amount > 0, "Amount must be greater than 0");
        IERC20(token).transfer(owner(), amount);
    }
}
