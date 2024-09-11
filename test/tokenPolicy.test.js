import { expect } from "chai";
import pkg from "hardhat";
const { ethers } = pkg;

describe("TokenPolicy", function () {
  let Kernel,
    kernel,
    YieldFuToken,
    yieldFuToken,
    MINTR,
    mintrModule,
    DEBASE,
    debaseModule,
    TokenPolicy,
    tokenPolicy;
  let owner, addr1, addr2;

  const initialSupply = ethers.parseEther("1000000");
  const dailyMintCap = ethers.parseEther("100000");
  const debaseRate = 300; // 3% debasement
  const debaseInterval = 86400; // 1 day
  const minDebaseThreshold = ethers.parseEther("500000");

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
      "YieldFu",
      "YFU",
      initialSupply,
      owner.address
    );
    await yieldFuToken.waitForDeployment();

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

    // Deploy the DEBASE module
    const DEBASE = await ethers.getContractFactory("DEBASE");
    debaseModule = await DEBASE.deploy(
      await kernel.getAddress(),
      await yieldFuToken.getAddress(),
      debaseRate,
      debaseInterval,
      minDebaseThreshold
    );
    await debaseModule.waitForDeployment();
    console.log(
      "TEST: DEBASE module deployed at:",
      await debaseModule.getAddress()
    );

    // Install the modules in Kernel
    await kernel.executeAction(0, await mintrModule.getAddress(), "0x");
    await kernel.executeAction(0, await debaseModule.getAddress(), "0x");
    console.log("TEST: Modules installed in Kernel");

    // Deploy and Activate TokenPolicy
    TokenPolicy = await ethers.getContractFactory("TokenPolicy");
    tokenPolicy = await TokenPolicy.deploy(
      await kernel.getAddress(),
      await yieldFuToken.getAddress()
    );
    await tokenPolicy.waitForDeployment();
    console.log(
      "TEST: TokenPolicy deployed at:",
      await tokenPolicy.getAddress()
    );
    await kernel
      .connect(owner)
      .executeAction(2, await tokenPolicy.getAddress(), "0x");
    console.log("TEST: TokenPolicy activated in Kernel");

    // Grant permission to TokenPolicy to set policy limit in MINTR
    const setPolicyLimitSelector =
      mintrModule.interface.getFunction("setPolicyLimit").selector;
    await kernel.setModulePermission(
      await mintrModule.getAddress(),
      await tokenPolicy.getAddress(),
      setPolicyLimitSelector,
      true
    );
    console.log("TEST: Permission granted for setting policy limit");

    // Grant permission for minting via the TOKEN module
    const mintSelector = yieldFuToken.interface.getFunction("mint").selector;
    await kernel.setModulePermission(
      await mintrModule.getAddress(),
      await tokenPolicy.getAddress(),
      mintSelector,
      true
    );

    // Grant permission to owner to call setPolicyLimit in MINTR
    await kernel.setModulePermission(
      await mintrModule.getAddress(),
      owner.address,
      setPolicyLimitSelector,
      true
    );
    console.log("TEST: Permission granted to owner for setting policy limit");

    // Set policy mint limit with correct signer
    await mintrModule
      .connect(owner)
      .setPolicyLimit(
        await tokenPolicy.getAddress(),
        ethers.parseEther("1000")
      );
  });

  it("should allow authorized minters to mint tokens", async function () {
    // Authorize addr1 as a minter
    await tokenPolicy.authorizeMinter(addr1.address);
    expect(await tokenPolicy.isAuthorizedMinter(addr1.address)).to.be.true;

    // Grant permission for minting via Kernel
    const mintSelector = mintrModule.interface.getFunction("mint").selector;
    await kernel.setModulePermission(
      await mintrModule.getAddress(),
      await tokenPolicy.getAddress(),
      mintSelector,
      true
    );

    // addr1 mints tokens via TokenPolicy
    await tokenPolicy
      .connect(addr1)
      .mint(addr1.address, ethers.parseEther("100"));
    const balance = await yieldFuToken.balanceOf(addr1.address);
    expect(balance).to.equal(ethers.parseEther("100"));
  });

  it("should prevent unauthorized minters from minting tokens", async function () {
    // Ensure addr2 is not authorized
    expect(await tokenPolicy.isAuthorizedMinter(addr2.address)).to.be.false;

    // Grant permission for minting via Kernel
    const mintSelector = mintrModule.interface.getFunction("mint").selector;
    await kernel.setModulePermission(
      await mintrModule.getAddress(),
      await tokenPolicy.getAddress(),
      mintSelector,
      true
    );

    // addr2 attempts to mint tokens via TokenPolicy
    await expect(
      tokenPolicy.connect(addr2).mint(addr2.address, ethers.parseEther("100"))
    ).to.be.revertedWithCustomError(tokenPolicy, "TokenPolicy_NotAuthorized");
  });

  it("should prevent minting tokens beyond the policy limit", async function () {
    // Authorize addr1 as a minter
    await tokenPolicy.authorizeMinter(addr1.address);
    expect(await tokenPolicy.isAuthorizedMinter(addr1.address)).to.be.true;

    // Set policy mint limit
    await mintrModule
      .connect(owner)
      .setPolicyLimit(await tokenPolicy.getAddress(), ethers.parseEther("500"));

    // Attempt to mint more than the limit
    await expect(
      tokenPolicy.connect(addr1).mint(addr1.address, ethers.parseEther("1000"))
    ).to.be.revertedWithCustomError(mintrModule, "MINTR_PolicyLimitExceeded");
  });

  it("should allow multiple authorized minters to mint tokens independently", async function () {
    // Authorize both addr1 and addr2 as minters
    await tokenPolicy.authorizeMinter(addr1.address);
    await tokenPolicy.authorizeMinter(addr2.address);

    // Verify that both are authorized
    expect(await tokenPolicy.isAuthorizedMinter(addr1.address)).to.be.true;
    expect(await tokenPolicy.isAuthorizedMinter(addr2.address)).to.be.true;

    // Mint tokens as addr1
    await tokenPolicy
      .connect(addr1)
      .mint(addr1.address, ethers.parseEther("100"));
    const balance1 = await yieldFuToken.balanceOf(addr1.address);
    expect(balance1).to.equal(ethers.parseEther("100"));

    // Mint tokens as addr2
    await tokenPolicy
      .connect(addr2)
      .mint(addr2.address, ethers.parseEther("200"));
    const balance2 = await yieldFuToken.balanceOf(addr2.address);
    expect(balance2).to.equal(ethers.parseEther("200"));
  });
  it("should allow authorized minters to burn tokens with sufficient allowance", async function () {
    // Authorize addr1 as a minter
    await tokenPolicy.authorizeMinter(addr1.address);

    // Mint some tokens
    await tokenPolicy
      .connect(addr1)
      .mint(addr1.address, ethers.parseEther("200"));

    // Set allowance for the MINTR module to burn tokens on behalf of addr1
    await yieldFuToken
      .connect(addr1)
      .approve(await mintrModule.getAddress(), ethers.parseEther("100"));

    // Burn half of the tokens using `burnFrom`
    await tokenPolicy
      .connect(addr1)
      .burn(addr1.address, ethers.parseEther("100"));

    // Verify the balance is reduced
    const balance = await yieldFuToken.balanceOf(addr1.address);
    expect(balance).to.equal(ethers.parseEther("100"));
  });

  it("should perform debase when authorized", async function () {
    // Grant permission for debasing via Kernel
    const debaseSelector =
      debaseModule.interface.getFunction("debase").selector;
    await kernel.setModulePermission(
      await debaseModule.getAddress(),
      await tokenPolicy.getAddress(),
      debaseSelector,
      true
    );

    // Fast forward time to pass debase interval
    await network.provider.send("evm_increaseTime", [debaseInterval]);
    await network.provider.send("evm_mine");

    // Perform debase via TokenPolicy
    await tokenPolicy.debase();

    // Fetch the debase index directly from the YieldFuToken
    const debaseIndex = await yieldFuToken.debaseIndex();
    console.log("Debase index:", debaseIndex);

    // Assert that the debase index was updated correctly
    expect(debaseIndex).to.equal(970000000000000000n);
  });
  it("should revoke minter authorization", async function () {
    // Authorize addr1 as a minter
    await tokenPolicy.authorizeMinter(addr1.address);
    expect(await tokenPolicy.isAuthorizedMinter(addr1.address)).to.be.true;

    // Revoke authorization
    await tokenPolicy.deauthorizeMinter(addr1.address);
    expect(await tokenPolicy.isAuthorizedMinter(addr1.address)).to.be.false;

    // Try to mint tokens after deauthorization
    await expect(
      tokenPolicy.connect(addr1).mint(addr1.address, ethers.parseEther("100"))
    ).to.be.revertedWithCustomError(tokenPolicy, "TokenPolicy_NotAuthorized");
  });
  it("should prevent debase before interval has passed", async function () {
    // Grant permission for debasing via Kernel
    const debaseSelector =
      debaseModule.interface.getFunction("debase").selector;
    await kernel.setModulePermission(
      await debaseModule.getAddress(),
      await tokenPolicy.getAddress(),
      debaseSelector,
      true
    );

    // Try to call debase before the interval
    await expect(tokenPolicy.debase()).to.be.revertedWithCustomError(
      debaseModule,
      "DEBASE_TooSoon"
    );
  });
  it("should prevent burning tokens without sufficient allowance", async function () {
    // Authorize addr1 as a minter
    await tokenPolicy.authorizeMinter(addr1.address);

    // Mint some tokens
    await tokenPolicy
      .connect(addr1)
      .mint(addr1.address, ethers.parseEther("200"));

    // Set insufficient allowance
    await yieldFuToken
      .connect(addr1)
      .approve(await mintrModule.getAddress(), ethers.parseEther("50"));

    // Attempt to burn more than allowed
    await expect(
      tokenPolicy.connect(addr1).burn(addr1.address, ethers.parseEther("100"))
    ).to.be.revertedWithCustomError(yieldFuToken, "ERC20InsufficientAllowance");
  });
  it("should prevent minting when mint limit is set to a very small value", async function () {
    // Authorize addr1 as a minter
    await tokenPolicy.authorizeMinter(addr1.address);
    expect(await tokenPolicy.isAuthorizedMinter(addr1.address)).to.be.true;

    // Set policy mint limit to a very small value
    await mintrModule
      .connect(owner)
      .setPolicyLimit(
        await tokenPolicy.getAddress(),
        ethers.parseEther("0.01")
      );

    // Attempt to mint more than the limit
    await expect(
      tokenPolicy.connect(addr1).mint(addr1.address, ethers.parseEther("1"))
    ).to.be.revertedWithCustomError(mintrModule, "MINTR_PolicyLimitExceeded");
  });
  it("should allow debase after a single interval has passed", async function () {
    // Grant permission for debasing via Kernel
    const debaseSelector =
      debaseModule.interface.getFunction("debase").selector;
    await kernel.setModulePermission(
      await debaseModule.getAddress(),
      await tokenPolicy.getAddress(),
      debaseSelector,
      true
    );

    // Fast forward time to pass one interval
    await network.provider.send("evm_increaseTime", [debaseInterval]);
    await network.provider.send("evm_mine");

    // Perform debase via TokenPolicy
    await tokenPolicy.debase();

    // Fetch the debase index directly from the YieldFuToken
    const debaseIndex = await yieldFuToken.debaseIndex();
    console.log("Debase index:", debaseIndex);

    // Assert that the debase index was updated correctly
    expect(debaseIndex).to.equal(970000000000000000n);
  });

  it("should prevent minting above the daily mint cap", async function () {
    // Authorize addr1 as a minter
    await tokenPolicy.authorizeMinter(addr1.address);
    expect(await tokenPolicy.isAuthorizedMinter(addr1.address)).to.be.true;

    // Attempt to mint more than the daily cap
    await expect(
      tokenPolicy
        .connect(addr1)
        .mint(addr1.address, ethers.parseEther("200000"))
    ).to.be.revertedWithCustomError(mintrModule, "MINTR_DailyCapExceeded");
  });
  it("should allow changing the debase rate", async function () {
    // Grant permission for changing debase rate via Kernel
    const changeDebaseRateSelector =
      debaseModule.interface.getFunction("changeDebaseRate").selector;

    // Grant TokenPolicy permission to call changeDebaseRate on DEBASE module
    await kernel.setModulePermission(
      await debaseModule.getAddress(),
      await tokenPolicy.getAddress(),
      changeDebaseRateSelector,
      true
    );

    // Change the debase rate using the DEBASE module through TokenPolicy
    await tokenPolicy.changeDebaseRate(500); // Set new debase rate to 5%

    // Verify the debase rate was updated
    const debaseRate = await debaseModule.debaseRate();
    expect(debaseRate).to.equal(500);
  });
  it("should allow multiple debases checking the debase index after each one", async function () {
    // Grant permission for debasing via Kernel
    const debaseSelector =
      debaseModule.interface.getFunction("debase").selector;
    await kernel.setModulePermission(
      await debaseModule.getAddress(),
      await tokenPolicy.getAddress(),
      debaseSelector,
      true
    );

    // First debase
    await network.provider.send("evm_increaseTime", [debaseInterval]);
    await network.provider.send("evm_mine");

    await tokenPolicy.debase();
    let debaseIndex1 = await yieldFuToken.debaseIndex();
    console.log("Debase index after first debase:", debaseIndex1.toString());
    expect(debaseIndex1).to.be.closeTo(970000000000000000n, 100000n); // Increased margin of error

    // Second debase
    await network.provider.send("evm_increaseTime", [debaseInterval]);
    await network.provider.send("evm_mine");

    await tokenPolicy.debase();
    let debaseIndex2 = await yieldFuToken.debaseIndex();
    console.log("Debase index after second debase:", debaseIndex2.toString());
    expect(debaseIndex2).to.be.closeTo(941090000000000000n, 100000n); // Increased margin of error

    // Third debase
    await network.provider.send("evm_increaseTime", [debaseInterval]);
    await network.provider.send("evm_mine");

    await tokenPolicy.debase();
    let debaseIndex3 = await yieldFuToken.debaseIndex();
    console.log("Debase index after third debase:", debaseIndex3.toString());
    expect(debaseIndex3).to.be.closeTo(913857300000000000n, 100000n); // Increased margin of error
  });
});
