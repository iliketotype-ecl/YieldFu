import { expect } from "chai";
import pkg from "hardhat";
const { ethers } = pkg;

describe("Kernel", function () {
  let kernel, owner, user1, user2;

  before(async function () {
    [owner, user1, user2] = await ethers.getSigners();
  });

  beforeEach(async function () {
    // Deploy Kernel
    const Kernel = await ethers.getContractFactory("Kernel");
    kernel = await Kernel.deploy();
  });

  it("Should set the right owner", async function () {
    expect(await kernel.executor()).to.equal(await owner.getAddress());
  });

  it("Should install modules correctly", async function () {
    // Install module example
    const moduleAddress = "0x123...";
    await kernel.executeAction(0, moduleAddress);
    const installedModule = await kernel.getModuleForKeycode("TOKEN");
    expect(installedModule).to.equal(moduleAddress);
  });

  // Add more Kernel related tests here
});
