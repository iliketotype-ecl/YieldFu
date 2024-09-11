import { expect } from "chai";
import pkg from "hardhat";
const { ethers } = pkg;

describe("MINTR", function () {
  let Kernel, kernel, YieldFuToken, yieldFuToken, MINTR, mintrModule;
  let owner, addr1, addr2;

  const initialSupply = ethers.parseEther("1000000");
  const dailyMintCap = ethers.parseEther("100000");

  beforeEach(async function () {
    [owner, addr1, addr2] = await ethers.getSigners();

    // Deploy the Kernel contract
    const Kernel = await ethers.getContractFactory("Kernel");
    kernel = await Kernel.deploy();
    await kernel.waitForDeployment();
    console.log("TEST: Kernel deployed at:", await kernel.getAddress());

    // Deploy the YieldFuToken
    const YieldFuToken = await ethers.getContractFactory("YieldFuToken");
    yieldFuToken = await YieldFuToken.deploy(
      await kernel.getAddress(),
      "YieldFu",
      "YFU",
      initialSupply,
      owner.address
    );
    await yieldFuToken.waitForDeployment();
    console.log(
      "TEST: YieldFuToken deployed at:",
      await yieldFuToken.getAddress()
    );

    // Deploy the MINTR module
    const MINTR = await ethers.getContractFactory("MINTR");
    mintrModule = await MINTR.deploy(
      await kernel.getAddress(),
      await yieldFuToken.getAddress(),
      dailyMintCap
    );
    await mintrModule.waitForDeployment();
    console.log(
      "TEST: MINTR module deployed at:",
      await mintrModule.getAddress()
    );

    // Install the MINTR module in Kernel
    await kernel.executeAction(0, await mintrModule.getAddress(), "0x"); // 0 = InstallModule
    console.log("TEST: MINTR module installed in Kernel");
  });
  it("should mint tokens if permission is granted", async function () {
    // Use correct mintSelector
    const mintSelector = mintrModule.interface.getFunction("mint").selector;

    // Grant permission for minting
    await kernel.setModulePermission(
      await mintrModule.getAddress(),
      addr1.address,
      mintSelector,
      true
    );
    console.log("TEST: Permission granted for minting");

    // Set policy mint limit for addr1
    await mintrModule
      .connect(owner)
      .setPolicyLimit(addr1.address, ethers.parseEther("1000")); // Set the limit to a value higher than the mint amount
    console.log("TEST: Policy limit set for addr1");

    // Mint tokens via MINTR
    await mintrModule
      .connect(addr1)
      .mint(addr1.address, ethers.parseEther("100"));
    console.log("TEST: Tokens minted");

    // Verify balance
    const balance = await yieldFuToken.balanceOf(addr1.address);
    expect(balance).to.equal(ethers.parseEther("100"));
  });

  it("should fail to mint tokens if permission is not granted", async function () {
    await expect(
      mintrModule.connect(addr1).mint(addr1.address, ethers.parseEther("100"))
    ).to.be.revertedWith("Module_PolicyNotPermitted");
  });

  it("should respect daily mint cap", async function () {
    const mintSelector = mintrModule.interface.getFunction("mint").selector;
    await kernel.setModulePermission(
      await mintrModule.getAddress(),
      addr1.address,
      mintSelector,
      true
    );

    // Set policy mint limit for addr1
    await mintrModule
      .connect(owner)
      .setPolicyLimit(addr1.address, ethers.parseEther("5000")); // Set a higher limit than daily cap

    // Attempt to mint more than the daily cap
    await expect(
      mintrModule
        .connect(addr1)
        .mint(addr1.address, ethers.parseEther("200000"))
    ).to.be.revertedWithCustomError(mintrModule, "MINTR_DailyCapExceeded");
  });

  it("should burn tokens if permission is granted", async function () {
    // Mint some tokens first
    const mintSelector = mintrModule.interface.getFunction("mint").selector;
    await kernel.setModulePermission(
      await mintrModule.getAddress(),
      addr1.address,
      mintSelector,
      true
    );
    await mintrModule
      .connect(addr1)
      .mint(addr1.address, ethers.parseEther("500"));

    // Grant permission for burning
    const burnSelector = mintrModule.interface.getFunction("burn").selector;
    await kernel.setModulePermission(
      mintrModule.address,
      addr1.address,
      burnSelector,
      true
    );

    // Burn tokens via MINTR
    await mintrModule
      .connect(addr1)
      .burn(addr1.address, ethers.parseEther("100"));

    // Verify balance after burning
    const balance = await yieldFuToken.balanceOf(addr1.address);
    expect(balance).to.equal(ethers.parseEther("400"));
  });
});
