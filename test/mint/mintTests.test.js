import { expect } from "chai";
import { deployContracts } from "../setup/deployContracts.test.js";

describe("Minting Tests", function () {
  let kernel,
    yieldFuToken,
    mintrModule,
    debaseModule,
    tokenPolicy,
    owner,
    addr1,
    addr2;

  const initialSupply = ethers.parseEther("1000000");
  const dailyMintCap = ethers.parseEther("100000");
  const debaseRate = 300; // 3% debasement
  const debaseInterval = 86400; // 1 day
  const minDebaseThreshold = ethers.parseEther("500000");

  beforeEach(async function () {
    const deployedContracts = await deployContracts({
      initialSupply,
      dailyMintCap,
      debaseRate,
      debaseInterval,
      minDebaseThreshold,
    });

    ({
      kernel,
      yieldFuToken,
      mintrModule,
      debaseModule,
      tokenPolicy,
      owner,
      addr1,
      addr2,
    } = deployedContracts);
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
});
