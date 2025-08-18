// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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

contract MockPermit2 is IPermit2 {
    mapping(address => mapping(address => uint256)) public allowance;
    mapping(address => uint256) public nonces;

    function permitTransferFrom(
        PermitTransferFrom calldata permit,
        SignatureTransferDetails calldata transferDetails,
        address owner,
        bytes calldata /* signature */
    ) external override {
        // 在真实环境中，这里会验证签名
        // 为了测试简化，我们直接执行转账
        // 为了测试简化，不严格检查过期时间
        require(permit.permitted.amount >= transferDetails.requestedAmount, "Insufficient permit amount");
        
        // 执行转账
        IERC20 token = IERC20(permit.permitted.token);
        require(token.transferFrom(owner, transferDetails.to, transferDetails.requestedAmount), "Transfer failed");
        
        // 增加nonce
        nonces[owner]++;
    }

    function approve(address token, address spender, uint256 amount) external {
        allowance[msg.sender][spender] = amount;
        IERC20(token).approve(spender, amount);
    }
}