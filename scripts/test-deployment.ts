import { ethers } from "hardhat";

async function main() {
    // 这里填入部署后的合约地址
    const permit2Address = "YOUR_PERMIT2_ADDRESS";
    const piggyAddress = "YOUR_PIGGY_ADDRESS";
    const usdtAddress = "YOUR_USDT_ADDRESS";
    
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