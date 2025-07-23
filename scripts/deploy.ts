import { ethers } from "hardhat";

async function main() {
    
    // 获取网络名称
    const network = await ethers.provider.getNetwork();
    console.log("当前网络:", network.name, "Chain ID:", network.chainId);

    // 部署 MultiTokenPiggy 合约
    console.log("正在部署MultiTokenPiggy合约...");
    const MultiTokenPiggy = await ethers.getContractFactory("MultiTokenPiggy");
    const piggy = await MultiTokenPiggy.deploy();
    await piggy.waitForDeployment();
    console.log("MultiTokenPiggy合约地址:", await piggy.getAddress());
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
}); 