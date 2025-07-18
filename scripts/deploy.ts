import { ethers } from "hardhat";

async function main() {
    // 指定WLD（ERC20）合约地址
    const WLD_ADDRESS = "0x2cFc85d8E48F8EAB294be644d9E25C3030863003";
    const PiggyFactory = await ethers.getContractFactory("Piggy");
    const Piggy = await PiggyFactory.deploy(WLD_ADDRESS);
    await Piggy.waitForDeployment();
    console.log("✅ Piggy已部署:", await Piggy.getAddress());
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
