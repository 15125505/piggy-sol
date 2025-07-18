import { ethers } from "hardhat";

async function main() {
    const StringTestFactory = await ethers.getContractFactory("StringTest");
    const stest = await StringTestFactory.deploy();
    await stest.waitForDeployment();
    console.log("✅ StringTest已部署:", await stest.getAddress());
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
