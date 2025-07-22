import { ethers } from "hardhat";

async function main() {
    const [deployer] = await ethers.getSigners();
    
    console.log("部署账户:", deployer.address);
    console.log("账户余额:", (await deployer.provider.getBalance(deployer.address)).toString());

    // 1. 部署MockPermit2合约
    console.log("正在部署MockPermit2合约...");
    const MockPermit2Factory = await ethers.getContractFactory("MockPermit2");
    const permit2 = await MockPermit2Factory.deploy();
    await permit2.waitForDeployment();
    console.log("MockPermit2合约地址:", await permit2.getAddress());

    // 2. 部署测试代币
    const TestToken = await ethers.getContractFactory("TestToken");
    
    const usdt = await TestToken.deploy("Test USDT", "USDT", 1000000);
    await usdt.waitForDeployment();
    console.log("USDT代币地址:", await usdt.getAddress());
    
    const usdc = await TestToken.deploy("Test USDC", "USDC", 1000000);
    await usdc.waitForDeployment();
    console.log("USDC代币地址:", await usdc.getAddress());
    
    const dai = await TestToken.deploy("Test DAI", "DAI", 1000000);
    await dai.waitForDeployment();
    console.log("DAI代币地址:", await dai.getAddress());

    // 3. 部署MultiTokenPiggy合约
    console.log("正在部署MultiTokenPiggy合约...");
    const MultiTokenPiggy = await ethers.getContractFactory("MultiTokenPiggy");
    const piggy = await MultiTokenPiggy.deploy(await permit2.getAddress());
    await piggy.waitForDeployment();
    console.log("MultiTokenPiggy合约地址:", await piggy.getAddress());

    // 输出部署信息
    console.log("\n=== 部署完成 ===");
    console.log("MockPermit2:", await permit2.getAddress());
    console.log("USDT:", await usdt.getAddress());
    console.log("USDC:", await usdc.getAddress());
    console.log("DAI:", await dai.getAddress());
    console.log("MultiTokenPiggy:", await piggy.getAddress());
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
