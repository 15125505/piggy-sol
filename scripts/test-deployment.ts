import { ethers } from "hardhat";

async function main() {
    // 这里填入部署后的合约地址
    const permit2Address = "0x5FbDB2315678afecb367f032d93F642f64180aa3";
    const piggyAddress = "0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9";
    const usdtAddress = "0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512";
    
    const [user] = await ethers.getSigners();
    
    // 获取合约实例
    const usdt = await ethers.getContractAt("TestToken", usdtAddress);
    const piggy = await ethers.getContractAt("MultiTokenPiggy", piggyAddress);
    
    // 给用户铸造一些测试代币
    await usdt.mint(user.address, ethers.parseEther("1000"));
    
    console.log("用户USDT余额:", await usdt.balanceOf(user.address));
    console.log("部署测试完成！");
}

main().catch(console.error); 