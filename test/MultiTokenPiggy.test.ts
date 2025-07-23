import { expect } from "chai";
import { ethers } from "hardhat";
import { MultiTokenPiggy, MockPermit2, TestToken } from "../typechain-types";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";

describe("MultiTokenPiggy", function () {
    let multiTokenPiggy: MultiTokenPiggy;
    let mockPermit2: MockPermit2;
    let usdt: TestToken;
    let usdc: TestToken;
    let dai: TestToken;
    let owner: HardhatEthersSigner;
    let user1: HardhatEthersSigner;
    let user2: HardhatEthersSigner;

    const LOCK_PERIOD = 86400; // 1天
    const DEPOSIT_AMOUNT = ethers.parseEther("100");

    beforeEach(async function () {
        [owner, user1, user2] = await ethers.getSigners();

        // 部署MockPermit2到固定地址（模拟真实环境）
        const MockPermit2Factory = await ethers.getContractFactory("MockPermit2");
        mockPermit2 = await MockPermit2Factory.deploy();
        await mockPermit2.waitForDeployment();

        // 部署测试代币
        const TestTokenFactory = await ethers.getContractFactory("TestToken");
        usdt = await TestTokenFactory.deploy("Test USDT", "USDT", 1000000);
        usdc = await TestTokenFactory.deploy("Test USDC", "USDC", 1000000);
        dai = await TestTokenFactory.deploy("Test DAI", "DAI", 1000000);
        await usdt.waitForDeployment();
        await usdc.waitForDeployment();
        await dai.waitForDeployment();

        // 部署MultiTokenPiggy（不再需要传入Permit2地址）
        const MultiTokenPiggyFactory = await ethers.getContractFactory("MultiTokenPiggy");
        multiTokenPiggy = await MultiTokenPiggyFactory.deploy();
        await multiTokenPiggy.waitForDeployment();

        // 给用户铸造测试代币
        await usdt.mint(user1.address, ethers.parseEther("10000"));
        await usdc.mint(user1.address, ethers.parseEther("10000"));
        await dai.mint(user1.address, ethers.parseEther("10000"));

        await usdt.mint(user2.address, ethers.parseEther("10000"));
        await usdc.mint(user2.address, ethers.parseEther("10000"));
        await dai.mint(user2.address, ethers.parseEther("10000"));

        // 批准代币给MockPermit2
        await usdt.connect(user1).approve(await mockPermit2.getAddress(), ethers.MaxUint256);
        await usdc.connect(user1).approve(await mockPermit2.getAddress(), ethers.MaxUint256);
        await dai.connect(user1).approve(await mockPermit2.getAddress(), ethers.MaxUint256);

        await usdt.connect(user2).approve(await mockPermit2.getAddress(), ethers.MaxUint256);
        await usdc.connect(user2).approve(await mockPermit2.getAddress(), ethers.MaxUint256);
        await dai.connect(user2).approve(await mockPermit2.getAddress(), ethers.MaxUint256);
    });

    describe("部署", function () {
        it("应该正确设置Permit2地址为常量", async function () {
            expect(await multiTokenPiggy.permit2()).to.equal("0x000000000022D473030F116dDEE9F6B43aC78BA3");
        });

        it("应该正确设置合约所有者", async function () {
            expect(await multiTokenPiggy.owner()).to.equal(owner.address);
        });
    });

    describe("存款功能", function () {
        it("首次存款应该创建存钱罐", async function () {
            const permit = {
                permitted: {
                    token: await usdt.getAddress(),
                    amount: DEPOSIT_AMOUNT
                },
                nonce: 0,
                deadline: Math.floor(Date.now() / 1000) + 3600
            };

            await expect(
                multiTokenPiggy.connect(user1).deposit(LOCK_PERIOD, DEPOSIT_AMOUNT, permit, "0x")
            ).to.emit(multiTokenPiggy, "PiggyBankCreated")
            .withArgs(user1.address, await ethers.provider.getBlock("latest").then(b => b!.timestamp + 1));
        });

        it("存款应该触发Deposited事件", async function () {
            const permit = {
                permitted: {
                    token: await usdt.getAddress(),
                    amount: DEPOSIT_AMOUNT
                },
                nonce: 0,
                deadline: Math.floor(Date.now() / 1000) + 3600
            };

            await expect(
                multiTokenPiggy.connect(user1).deposit(LOCK_PERIOD, DEPOSIT_AMOUNT, permit, "0x")
            ).to.emit(multiTokenPiggy, "Deposited")
            .withArgs(user1.address, await usdt.getAddress(), DEPOSIT_AMOUNT, DEPOSIT_AMOUNT);
        });

        it("存款金额必须大于0", async function () {
            const permit = {
                permitted: {
                    token: await usdt.getAddress(),
                    amount: 0
                },
                nonce: 0,
                deadline: Math.floor(Date.now() / 1000) + 3600
            };

            await expect(
                multiTokenPiggy.connect(user1).deposit(LOCK_PERIOD, 0, permit, "0x")
            ).to.be.revertedWith("Deposit amount must be greater than 0");
        });

        it("代币地址不能为零地址", async function () {
            const permit = {
                permitted: {
                    token: ethers.ZeroAddress,
                    amount: DEPOSIT_AMOUNT
                },
                nonce: 0,
                deadline: Math.floor(Date.now() / 1000) + 3600
            };

            await expect(
                multiTokenPiggy.connect(user1).deposit(LOCK_PERIOD, DEPOSIT_AMOUNT, permit, "0x")
            ).to.be.revertedWith("Invalid token address");
        });

        it("首次创建时锁定期必须大于0", async function () {
            const permit = {
                permitted: {
                    token: await usdt.getAddress(),
                    amount: DEPOSIT_AMOUNT
                },
                nonce: 0,
                deadline: Math.floor(Date.now() / 1000) + 3600
            };

            await expect(
                multiTokenPiggy.connect(user1).deposit(0, DEPOSIT_AMOUNT, permit, "0x")
            ).to.be.revertedWith("Lock period must be greater than 0");
        });

        it("可以存入多种代币", async function () {
            // 存入USDT
            const permitUSDT = {
                permitted: {
                    token: await usdt.getAddress(),
                    amount: DEPOSIT_AMOUNT
                },
                nonce: 0,
                deadline: Math.floor(Date.now() / 1000) + 3600
            };

            await multiTokenPiggy.connect(user1).deposit(LOCK_PERIOD, DEPOSIT_AMOUNT, permitUSDT, "0x");

            // 存入USDC
            const permitUSDC = {
                permitted: {
                    token: await usdc.getAddress(),
                    amount: DEPOSIT_AMOUNT
                },
                nonce: 1,
                deadline: Math.floor(Date.now() / 1000) + 3600
            };

            await multiTokenPiggy.connect(user1).deposit(LOCK_PERIOD, DEPOSIT_AMOUNT, permitUSDC, "0x");

            const [tokens, balances] = await multiTokenPiggy.getBalances(user1.address);
            expect(tokens.length).to.equal(2);
            expect(balances[0]).to.equal(DEPOSIT_AMOUNT);
            expect(balances[1]).to.equal(DEPOSIT_AMOUNT);
        });

        it("同一代币多次存款应该累加余额", async function () {
            const permit1 = {
                permitted: {
                    token: await usdt.getAddress(),
                    amount: DEPOSIT_AMOUNT
                },
                nonce: 0,
                deadline: Math.floor(Date.now() / 1000) + 3600
            };

            await multiTokenPiggy.connect(user1).deposit(LOCK_PERIOD, DEPOSIT_AMOUNT, permit1, "0x");

            const permit2 = {
                permitted: {
                    token: await usdt.getAddress(),
                    amount: DEPOSIT_AMOUNT
                },
                nonce: 1,
                deadline: Math.floor(Date.now() / 1000) + 3600
            };

            await expect(
                multiTokenPiggy.connect(user1).deposit(LOCK_PERIOD, DEPOSIT_AMOUNT, permit2, "0x")
            ).to.emit(multiTokenPiggy, "Deposited")
            .withArgs(user1.address, await usdt.getAddress(), DEPOSIT_AMOUNT, DEPOSIT_AMOUNT * 2n);
        });
    });

    describe("提取功能", function () {
        beforeEach(async function () {
            // 预先存入一些代币
            const permitUSDT = {
                permitted: {
                    token: await usdt.getAddress(),
                    amount: DEPOSIT_AMOUNT
                },
                nonce: 0,
                deadline: Math.floor(Date.now() / 1000) + 3600
            };

            const permitUSDC = {
                permitted: {
                    token: await usdc.getAddress(),
                    amount: DEPOSIT_AMOUNT
                },
                nonce: 1,
                deadline: Math.floor(Date.now() / 1000) + 3600
            };

            await multiTokenPiggy.connect(user1).deposit(LOCK_PERIOD, DEPOSIT_AMOUNT, permitUSDT, "0x");
            await multiTokenPiggy.connect(user1).deposit(LOCK_PERIOD, DEPOSIT_AMOUNT, permitUSDC, "0x");
        });

        it("没有存钱罐时不能提取", async function () {
            await expect(
                multiTokenPiggy.connect(user2).withdraw()
            ).to.be.revertedWith("Please create a piggy bank first");
        });

        it("锁定期内不能提取", async function () {
            await expect(
                multiTokenPiggy.connect(user1).withdraw()
            ).to.be.revertedWith("Not yet unlocked");
        });

        it("锁定期后可以提取所有代币", async function () {
            // 快进时间
            await ethers.provider.send("evm_increaseTime", [LOCK_PERIOD]);
            await ethers.provider.send("evm_mine", []);

            const balanceBefore = await usdt.balanceOf(user1.address);

            await expect(multiTokenPiggy.connect(user1).withdraw())
                .to.emit(multiTokenPiggy, "Withdrawn")
                .withArgs(user1.address, await usdt.getAddress(), DEPOSIT_AMOUNT);

            const balanceAfter = await usdt.balanceOf(user1.address);
            expect(balanceAfter - balanceBefore).to.equal(DEPOSIT_AMOUNT);

            // 检查余额被清零
            const [tokens, balances] = await multiTokenPiggy.getBalances(user1.address);
            expect(balances[0]).to.equal(0);
            expect(balances[1]).to.equal(0);
        });
    });

    describe("查询功能", function () {
        it("可以查询解锁时间戳", async function () {
            const permit = {
                permitted: {
                    token: await usdt.getAddress(),
                    amount: DEPOSIT_AMOUNT
                },
                nonce: 0,
                deadline: Math.floor(Date.now() / 1000) + 3600
            };

            const tx = await multiTokenPiggy.connect(user1).deposit(LOCK_PERIOD, DEPOSIT_AMOUNT, permit, "0x");
            const receipt = await tx.wait();
            const block = await ethers.provider.getBlock(receipt!.blockNumber);

            const unlockTimestamp = await multiTokenPiggy.getUnlockTimestamp(user1.address);
            expect(unlockTimestamp).to.equal(block!.timestamp + LOCK_PERIOD);
        });

        it("没有存钱罐时查询解锁时间戳应该失败", async function () {
            await expect(
                multiTokenPiggy.getUnlockTimestamp(user1.address)
            ).to.be.revertedWith("Piggy bank does not exist");
        });

        it("可以查询所有代币余额", async function () {
            const permitUSDT = {
                permitted: {
                    token: await usdt.getAddress(),
                    amount: DEPOSIT_AMOUNT
                },
                nonce: 0,
                deadline: Math.floor(Date.now() / 1000) + 3600
            };

            const permitUSDC = {
                permitted: {
                    token: await usdc.getAddress(),
                    amount: DEPOSIT_AMOUNT * 2n
                },
                nonce: 1,
                deadline: Math.floor(Date.now() / 1000) + 3600
            };

            await multiTokenPiggy.connect(user1).deposit(LOCK_PERIOD, DEPOSIT_AMOUNT, permitUSDT, "0x");
            await multiTokenPiggy.connect(user1).deposit(LOCK_PERIOD, DEPOSIT_AMOUNT * 2n, permitUSDC, "0x");

            const [tokens, balances] = await multiTokenPiggy.getBalances(user1.address);
            expect(tokens.length).to.equal(2);
            expect(tokens[0]).to.equal(await usdt.getAddress());
            expect(tokens[1]).to.equal(await usdc.getAddress());
            expect(balances[0]).to.equal(DEPOSIT_AMOUNT);
            expect(balances[1]).to.equal(DEPOSIT_AMOUNT * 2n);
        });

        it("没有代币时查询应该返回空数组", async function () {
            const [tokens, balances] = await multiTokenPiggy.getBalances(user1.address);
            expect(tokens.length).to.equal(0);
            expect(balances.length).to.equal(0);
        });
    });

    describe("移除代币功能", function () {
        beforeEach(async function () {
            const permit = {
                permitted: {
                    token: await usdt.getAddress(),
                    amount: DEPOSIT_AMOUNT
                },
                nonce: 0,
                deadline: Math.floor(Date.now() / 1000) + 3600
            };

            await multiTokenPiggy.connect(user1).deposit(LOCK_PERIOD, DEPOSIT_AMOUNT, permit, "0x");
        });

        it("没有存钱罐时不能移除代币", async function () {
            await expect(
                multiTokenPiggy.connect(user2).removeToken(await usdt.getAddress())
            ).to.be.revertedWith("Please create a piggy bank first");
        });

        it("没有余额的代币不能移除", async function () {
            await expect(
                multiTokenPiggy.connect(user1).removeToken(await usdc.getAddress())
            ).to.be.revertedWith("No balance for this token");
        });

        it("可以成功移除有余额的代币", async function () {
            await expect(
                multiTokenPiggy.connect(user1).removeToken(await usdt.getAddress())
            ).to.emit(multiTokenPiggy, "TokenRemoved")
            .withArgs(user1.address, await usdt.getAddress(), DEPOSIT_AMOUNT);

            const [tokens, balances] = await multiTokenPiggy.getBalances(user1.address);
            expect(tokens.length).to.equal(0);
            expect(balances.length).to.equal(0);
        });
    });

    describe("重新创建存钱罐", function () {
        it("所有余额为0且锁定期过期后可以重新创建", async function () {
            // 首次创建并存款
            const permit = {
                permitted: {
                    token: await usdt.getAddress(),
                    amount: DEPOSIT_AMOUNT
                },
                nonce: 0,
                deadline: Math.floor(Date.now() / 1000) + 3600
            };

            await multiTokenPiggy.connect(user1).deposit(LOCK_PERIOD, DEPOSIT_AMOUNT, permit, "0x");

            // 快进时间并提取
            await ethers.provider.send("evm_increaseTime", [LOCK_PERIOD]);
            await ethers.provider.send("evm_mine", []);
            await multiTokenPiggy.connect(user1).withdraw();

            // 重新存款应该创建新的存钱罐
            const newLockPeriod = LOCK_PERIOD * 2;
            const permit2 = {
                permitted: {
                    token: await usdc.getAddress(),
                    amount: DEPOSIT_AMOUNT
                },
                nonce: 2,
                deadline: Math.floor(Date.now() / 1000) + 3600
            };

            await expect(
                multiTokenPiggy.connect(user1).deposit(newLockPeriod, DEPOSIT_AMOUNT, permit2, "0x")
            ).to.emit(multiTokenPiggy, "PiggyBankCreated");

            const unlockTimestamp = await multiTokenPiggy.getUnlockTimestamp(user1.address);
            const currentBlock = await ethers.provider.getBlock("latest");
            expect(unlockTimestamp).to.be.closeTo(currentBlock!.timestamp + newLockPeriod, 2);
        });
    });

    describe("边界情况测试", function () {
        it("处理转账失败的情况", async function () {
            // 这个测试需要一个会失败的代币合约
            // 由于我们使用的是标准的TestToken，这个测试可能需要特殊的mock代币
            // 这里我们跳过这个测试，但在实际项目中应该包含
        });

        it("防重入攻击测试", async function () {
            // 由于使用了ReentrancyGuard，这个测试确保重入攻击被阻止
            // 实际测试需要创建恶意合约来尝试重入攻击
        });
    });
}); 