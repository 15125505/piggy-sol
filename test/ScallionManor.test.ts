import { expect } from "chai";
import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import {
    ScallionManorTest,
    MockERC20,
    MockPermit2
} from "../typechain-types";

describe("ScallionManor", function () {
    let scallionManor: ScallionManorTest;
    let wbtcToken: MockERC20;
    let wldToken: MockERC20;
    let mockPermit2: MockPermit2;
    let owner: SignerWithAddress;
    let user1: SignerWithAddress;
    let user2: SignerWithAddress;
    let user3: SignerWithAddress;
    let fallbackAddress: SignerWithAddress;

    const MANOR_ACCESS_PRICE = ethers.parseEther("100"); // 100 WLD
    const FORCE_CHANGE_FEE = ethers.parseEther("50");    // 50 WLD
    const DEPOSIT_AMOUNT = ethers.parseEther("1");       // 1 WBTC
    const LOCK_PERIOD = 86400 * 30; // 30 days

    beforeEach(async function () {
        [owner, user1, user2, user3, fallbackAddress] = await ethers.getSigners();

        // 部署Mock代币
        const MockERC20 = await ethers.getContractFactory("MockERC20");
        wbtcToken = await MockERC20.deploy("Wrapped Bitcoin", "WBTC");
        wldToken = await MockERC20.deploy("Worldcoin", "WLD");

        // 部署MockPermit2
        const MockPermit2 = await ethers.getContractFactory("MockPermit2");
        mockPermit2 = await MockPermit2.deploy();

        // 部署ScallionManor测试合约
        const ScallionManorTest = await ethers.getContractFactory("ScallionManorTest");
        scallionManor = await ScallionManorTest.deploy(
            await wbtcToken.getAddress(),
            await wldToken.getAddress(),
            await mockPermit2.getAddress(),
            MANOR_ACCESS_PRICE,
            FORCE_CHANGE_FEE,
            fallbackAddress.address
        );

        // 为用户铸造代币
        await wbtcToken.mint(user1.address, ethers.parseEther("10"));
        await wbtcToken.mint(user2.address, ethers.parseEther("10"));
        await wldToken.mint(user1.address, ethers.parseEther("1000"));
        await wldToken.mint(user2.address, ethers.parseEther("1000"));
        await wldToken.mint(user3.address, ethers.parseEther("1000"));

        // 批准代币给MockPermit2
        await wbtcToken.connect(user1).approve(await mockPermit2.getAddress(), ethers.parseEther("10"));
        await wbtcToken.connect(user2).approve(await mockPermit2.getAddress(), ethers.parseEther("10"));
        await wldToken.connect(user1).approve(await mockPermit2.getAddress(), ethers.parseEther("1000"));
        await wldToken.connect(user2).approve(await mockPermit2.getAddress(), ethers.parseEther("1000"));
        await wldToken.connect(user3).approve(await mockPermit2.getAddress(), ethers.parseEther("1000"));
    });

    // 辅助函数：创建Permit结构
    function createPermit(tokenAddress: string, amount: bigint, nonce: number = 0) {
        return {
            permitted: {
                token: tokenAddress,
                amount: amount
            },
            nonce: nonce,
            deadline: Math.floor(Date.now() / 1000) + 86400 * 365 // 1年后过期
        };
    }

    describe("构造函数", function () {
        it("应该正确初始化合约", async function () {
            expect(await scallionManor.wbtcToken()).to.equal(await wbtcToken.getAddress());
            expect(await scallionManor.wldToken()).to.equal(await wldToken.getAddress());
            expect(await scallionManor.manorAccessPrice()).to.equal(MANOR_ACCESS_PRICE);
            expect(await scallionManor.forceChangeFee()).to.equal(FORCE_CHANGE_FEE);
            expect(await scallionManor.fallbackAddress()).to.equal(fallbackAddress.address);
        });
    });

    describe("庄园权限购买", function () {
        it("应该允许用户购买庄园权限", async function () {
            const permit = createPermit(await wldToken.getAddress(), MANOR_ACCESS_PRICE);

            await expect(
                scallionManor.connect(user1).purchaseManorAccess(permit, "0x")
            ).to.emit(scallionManor, "ManorAccessPurchased")
             .withArgs(user1.address, MANOR_ACCESS_PRICE)
             .and.to.emit(scallionManor, "ActivityUpdated");

            expect(await scallionManor.hasManorAccess(user1.address)).to.be.true;
        });

        it("应该拒绝重复购买庄园权限", async function () {
            const permit = createPermit(await wldToken.getAddress(), MANOR_ACCESS_PRICE);

            await scallionManor.connect(user1).purchaseManorAccess(permit, "0x");

            const permit2 = createPermit(await wldToken.getAddress(), MANOR_ACCESS_PRICE, 1);
            await expect(
                scallionManor.connect(user1).purchaseManorAccess(permit2, "0x")
            ).to.be.revertedWith("Already has manor access");
        });

        it("应该拒绝错误的支付金额", async function () {
            const wrongPermit = createPermit(await wldToken.getAddress(), ethers.parseEther("50"));

            await expect(
                scallionManor.connect(user1).purchaseManorAccess(wrongPermit, "0x")
            ).to.be.revertedWith("Must pay exact manor access price");
        });
    });

    describe("WBTC存取", function () {
        beforeEach(async function () {
            // 先购买庄园权限
            const permit = createPermit(await wldToken.getAddress(), MANOR_ACCESS_PRICE);
            await scallionManor.connect(user1).purchaseManorAccess(permit, "0x");
        });

        it("应该允许存入WBTC", async function () {
            const permit = createPermit(await wbtcToken.getAddress(), DEPOSIT_AMOUNT);

            await expect(
                scallionManor.connect(user1).depositWBTC(LOCK_PERIOD, permit, "0x")
            ).to.emit(scallionManor, "WBTCDeposited")
             .withArgs(user1.address, DEPOSIT_AMOUNT, DEPOSIT_AMOUNT, LOCK_PERIOD);

            const manorInfo = await scallionManor.getManorInfo(user1.address);
            expect(manorInfo.wbtcBalance).to.equal(DEPOSIT_AMOUNT);
        });

        it("应该在锁定期结束后允许提取", async function () {
            const permit = createPermit(await wbtcToken.getAddress(), DEPOSIT_AMOUNT);
            await scallionManor.connect(user1).depositWBTC(LOCK_PERIOD, permit, "0x");

            // 快进时间到锁定期结束
            await ethers.provider.send("evm_increaseTime", [LOCK_PERIOD + 1]);
            await ethers.provider.send("evm_mine");

            const balanceBefore = await wbtcToken.balanceOf(user1.address);

            await expect(
                scallionManor.connect(user1).withdrawWBTC()
            ).to.emit(scallionManor, "WBTCWithdrawn")
             .withArgs(user1.address, DEPOSIT_AMOUNT, user1.address);

            const balanceAfter = await wbtcToken.balanceOf(user1.address);
            expect(balanceAfter - balanceBefore).to.equal(DEPOSIT_AMOUNT);
        });

        it("应该拒绝在锁定期内提取", async function () {
            const permit = createPermit(await wbtcToken.getAddress(), DEPOSIT_AMOUNT);
            await scallionManor.connect(user1).depositWBTC(LOCK_PERIOD, permit, "0x");

            await expect(
                scallionManor.connect(user1).withdrawWBTC()
            ).to.be.revertedWith("Still locked");
        });
    });

    describe("活跃时间管理", function () {
        beforeEach(async function () {
            const permit = createPermit(await wldToken.getAddress(), MANOR_ACCESS_PRICE);
            await scallionManor.connect(user1).purchaseManorAccess(permit, "0x");
        });

        it("应该允许用户刷新活跃时间", async function () {
            const timestampBefore = (await scallionManor.getManorInfo(user1.address)).lastActiveTime;

            // 等待1秒
            await ethers.provider.send("evm_increaseTime", [1]);
            await ethers.provider.send("evm_mine");

            await expect(
                scallionManor.connect(user1).refreshActivity()
            ).to.emit(scallionManor, "ActivityUpdated");

            const timestampAfter = (await scallionManor.getManorInfo(user1.address)).lastActiveTime;
            expect(timestampAfter).to.be.greaterThan(timestampBefore);
        });

        it("应该拒绝没有庄园权限的用户刷新活跃时间", async function () {
            await expect(
                scallionManor.connect(user2).refreshActivity()
            ).to.be.revertedWith("Must have manor access");
        });
    });

    describe("开发者打赏", function () {
        it("应该允许任何人打赏开发者", async function () {
            const tipAmount = ethers.parseEther("10");
            const message = "感谢开发者的辛苦工作！🎉";
            const permit = createPermit(await wldToken.getAddress(), tipAmount);

            await expect(
                scallionManor.connect(user1).tipDeveloper(permit, "0x", message)
            ).to.emit(scallionManor, "DeveloperTipped")
             .withArgs(user1.address, tipAmount, message);

            // 验证合约收到了WLD
            const contractBalance = await wldToken.balanceOf(await scallionManor.getAddress());
            expect(contractBalance).to.equal(tipAmount);
        });

        it("应该在有庄园权限时自动更新活跃时间", async function () {
            // 先购买庄园权限
            const accessPermit = createPermit(await wldToken.getAddress(), MANOR_ACCESS_PRICE);
            await scallionManor.connect(user1).purchaseManorAccess(accessPermit, "0x");

            const tipAmount = ethers.parseEther("10");
            const tipPermit = createPermit(await wldToken.getAddress(), tipAmount, 1);

            await expect(
                scallionManor.connect(user1).tipDeveloper(tipPermit, "0x", "测试打赏")
            ).to.emit(scallionManor, "ActivityUpdated");
        });

        it("应该拒绝非WLD代币打赏", async function () {
            const permit = createPermit(await wbtcToken.getAddress(), ethers.parseEther("1"));

            await expect(
                scallionManor.connect(user1).tipDeveloper(permit, "0x", "测试")
            ).to.be.revertedWith("Must tip with WLD");
        });

        it("应该拒绝零金额打赏", async function () {
            const permit = createPermit(await wldToken.getAddress(), 0n);

            await expect(
                scallionManor.connect(user1).tipDeveloper(permit, "0x", "测试")
            ).to.be.revertedWith("Tip amount must be greater than 0");
        });
    });

    describe("权限管理", function () {
        it("应该正确识别有权提取的用户", async function () {
            // 购买庄园权限并存入WBTC
            const accessPermit = createPermit(await wldToken.getAddress(), MANOR_ACCESS_PRICE);
            await scallionManor.connect(user1).purchaseManorAccess(accessPermit, "0x");

            const depositPermit = createPermit(await wbtcToken.getAddress(), DEPOSIT_AMOUNT);
            await scallionManor.connect(user1).depositWBTC(LOCK_PERIOD, depositPermit, "0x");

            // 用户活跃时应该返回用户自己
            expect(await scallionManor.getWithdrawer(user1.address)).to.equal(user1.address);

            // 模拟用户不活跃（365天后）
            await ethers.provider.send("evm_increaseTime", [365 * 24 * 3600 + 1]);
            await ethers.provider.send("evm_mine");

            // 没有继承人时应该返回兜底地址
            expect(await scallionManor.getWithdrawer(user1.address)).to.equal(fallbackAddress.address);
        });
    });

    describe("管理员功能", function () {
        it("应该允许管理员提取WLD费用", async function () {
            // 先让用户打赏一些WLD
            const tipAmount = ethers.parseEther("100");
            const permit = createPermit(await wldToken.getAddress(), tipAmount);
            await scallionManor.connect(user1).tipDeveloper(permit, "0x", "测试打赏");

            const ownerBalanceBefore = await wldToken.balanceOf(owner.address);

            await scallionManor.connect(owner).withdrawWLD();

            const ownerBalanceAfter = await wldToken.balanceOf(owner.address);
            expect(ownerBalanceAfter - ownerBalanceBefore).to.equal(tipAmount);
        });

        it("应该拒绝非管理员提取WLD", async function () {
            await expect(
                scallionManor.connect(user1).withdrawWLD()
            ).to.be.revertedWithCustomError(scallionManor, "OwnableUnauthorizedAccount");
        });
    });

    describe("边界测试", function () {
        it("应该正确处理多次存入", async function () {
            const accessPermit = createPermit(await wldToken.getAddress(), MANOR_ACCESS_PRICE);
            await scallionManor.connect(user1).purchaseManorAccess(accessPermit, "0x");

            // 第一次存入
            const firstPermit = createPermit(await wbtcToken.getAddress(), DEPOSIT_AMOUNT);
            await scallionManor.connect(user1).depositWBTC(LOCK_PERIOD, firstPermit, "0x");

            // 第二次存入（同一锁定期）
            const secondPermit = createPermit(await wbtcToken.getAddress(), DEPOSIT_AMOUNT, 1);
            await scallionManor.connect(user1).depositWBTC(LOCK_PERIOD, secondPermit, "0x");

            const manorInfo = await scallionManor.getManorInfo(user1.address);
            expect(manorInfo.wbtcBalance).to.equal(DEPOSIT_AMOUNT * 2n);
        });

        it("应该正确处理UTF-8中文消息", async function () {
            const messages: string[] = [
                "感谢开发者！",
                "这是一个测试消息 🎉",
                "支持中文字符测试",
                "🚀 区块链技术很棒！"
            ];

            for (let i = 0; i < messages.length; i++) {
                const permit = createPermit(await wldToken.getAddress(), ethers.parseEther("1"), i);

                await expect(
                    scallionManor.connect(user1).tipDeveloper(permit, "0x", messages[i])
                ).to.emit(scallionManor, "DeveloperTipped")
                 .withArgs(user1.address, ethers.parseEther("1"), messages[i]);
            }
        });
    });
});
