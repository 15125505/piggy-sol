// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts/utils/Strings.sol";

/// @title String Test Contract
/// @author zhoufeng
/// @notice 用于测试OpenZeppelin的Strings库功能
contract StringTest {
    using Strings for uint256;
    using Strings for address;
    
    /// @dev 存储测试字符串
    string public testString;
    
    /// @dev 存储测试数字
    uint256 public testNumber;
    
    /// @dev 存储测试地址
    address public testAddress;
    
    event StringUpdated(string oldString, string newString);
    event NumberUpdated(uint256 oldNumber, uint256 newNumber);
    event AddressUpdated(address oldAddress, address newAddress);
    
    constructor() {
        testString = "Hello.....";
        testNumber = 42;
        testAddress = address(this);
    }
    
    /// @notice 设置测试字符串
    /// @param _newString 新的测试字符串
    function setTestString(string memory _newString) external {
        string memory oldString = testString;
        testString = _newString;
        emit StringUpdated(oldString, _newString);
    }
    
    /// @notice 设置测试数字
    /// @param _newNumber 新的测试数字
    function setTestNumber(uint256 _newNumber) external {
        uint256 oldNumber = testNumber;
        testNumber = _newNumber;
        emit NumberUpdated(oldNumber, _newNumber);
    }
    
    /// @notice 设置测试地址
    /// @param _newAddress 新的测试地址
    function setTestAddress(address _newAddress) external {
        address oldAddress = testAddress;
        testAddress = _newAddress;
        emit AddressUpdated(oldAddress, _newAddress);
    }
    
    /// @notice 获取数字的字符串表示
    /// @param _number 要转换的数字
    /// @return 数字的字符串表示
    function getNumberAsString(uint256 _number) external pure returns (string memory) {
        return _number.toString();
    }
    
    /// @notice 获取地址的字符串表示
    /// @param _addr 要转换的地址
    /// @return 地址的字符串表示
    function getAddressAsString(address _addr) external pure returns (string memory) {
        return _addr.toHexString();
    }
    
    /// @notice 获取当前测试数字的字符串表示
    /// @return 当前测试数字的字符串表示
    function getCurrentNumberAsString() external view returns (string memory) {
        return testNumber.toString();
    }
    
    /// @notice 获取当前测试地址的字符串表示
    /// @return 当前测试地址的字符串表示
    function getCurrentAddressAsString() external view returns (string memory) {
        return testAddress.toHexString();
    }
    
    /// @notice 获取带前缀的地址字符串表示
    /// @param _addr 要转换的地址
    /// @return 带前缀的地址字符串表示
    function getAddressWithPrefix(address _addr) external pure returns (string memory) {
        return _addr.toHexString(20);
    }
    
    /// @notice 获取当前测试地址的带前缀字符串表示
    /// @return 当前测试地址的带前缀字符串表示
    function getCurrentAddressWithPrefix() external view returns (string memory) {
        return testAddress.toHexString(20);
    }
    
    /// @notice 测试字符串连接功能
    /// @param _str1 第一个字符串
    /// @param _str2 第二个字符串
    /// @return 连接后的字符串
    function concatenateStrings(string memory _str1, string memory _str2) external pure returns (string memory) {
        return string(abi.encodePacked(_str1, _str2));
    }
    
    /// @notice 获取合约信息的字符串表示
    /// @return 包含合约信息的字符串
    function getContractInfo() external view returns (string memory) {
        return string(abi.encodePacked(
            "Contract Address: ",
            address(this).toHexString(),
            ", Test Number: ",
            testNumber.toString(),
            ", Test String: ",
            testString
        ));
    }
    
    /// @notice 测试大数字的字符串转换
    /// @param _largeNumber 大数字
    /// @return 大数字的字符串表示
    function testLargeNumber(uint256 _largeNumber) external pure returns (string memory) {
        return _largeNumber.toString();
    }
    
    /// @notice 测试零值的字符串转换
    /// @return 零值的字符串表示
    function testZeroValue() external pure returns (string memory) {
        return uint256(0).toString();
    }
    
    /// @notice 测试最大值的字符串转换
    /// @return 最大值的字符串表示
    function testMaxValue() external pure returns (string memory) {
        return type(uint256).max.toString();
    }
} 