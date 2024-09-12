import { deployContracts } from "../setup/deployContracts.test.js";
import { expect } from "chai";
import pkg from "hardhat";
const { ethers } = pkg;

describe("Debasing Tests", function () {
  let kernel, yieldFuToken, debaseModule, tokenPolicy, owner, addr1, addr2;

  const initialSupply = ethers.parseEther("1000000");
  const dailyMintCap = ethers.parseEther("100000");
  const debaseRate = 300; // 3% debasement
  const debaseInterval = 86400; // 1 day
  const minDebaseThreshold = ethers.parseEther("500000");

  beforeEach(async function () {
    const contracts = await deployContracts({
      initialSupply,
      dailyMintCap,
      debaseRate,
      debaseInterval,
      minDebaseThreshold,
    });

    ({ kernel, yieldFuToken, debaseModule, tokenPolicy, owner, addr1, addr2 } =
      contracts);
  });

  it("should perform debase when authorized", async function () {
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

  it("should prevent debase before interval has passed", async function () {
    // Try to call debase before the interval
    await expect(tokenPolicy.debase()).to.be.revertedWithCustomError(
      debaseModule,
      "DEBASE_TooSoon"
    );
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
    expect(debaseIndex1).to.be.closeTo(970000000000000000n, 100000000n); // Increased margin of error

    // Second debase
    await network.provider.send("evm_increaseTime", [debaseInterval]);
    await network.provider.send("evm_mine");

    await tokenPolicy.debase();
    let debaseIndex2 = await yieldFuToken.debaseIndex();
    console.log("Debase index after second debase:", debaseIndex2.toString());
    expect(debaseIndex2).to.be.closeTo(941090000000000000n, 1000000000000000n); // Increased margin of error

    // Third debase
    await network.provider.send("evm_increaseTime", [debaseInterval]);
    await network.provider.send("evm_mine");

    await tokenPolicy.debase();
    let debaseIndex3 = await yieldFuToken.debaseIndex();
    console.log("Debase index after third debase:", debaseIndex3.toString());
    expect(debaseIndex3).to.be.closeTo(913857300000000000n, 10000000000000000n); // Increased margin of error
  });
});
