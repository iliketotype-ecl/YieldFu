import { expect } from "chai";
import pkg from "hardhat";
const { ethers } = pkg;

describe("Kernel", function () {
  let Kernel, kernel, MINTR, mintrModule, TokenPolicy, tokenPolicy;
  let owner, addr1;

  beforeEach(async function () {
    [owner, addr1] = await ethers.getSigners();

    // Deploy the Kernel contract
    const Kernel = await ethers.getContractFactory("Kernel");
    kernel = await Kernel.deploy();
    console.log("Kernel deployed at:", await kernel.getAddress());

    // Deploy a mock MINTR module
    const MINTR = await ethers.getContractFactory("MINTR");
    mintrModule = await MINTR.deploy(
      await kernel.getAddress(),
      addr1.address,
      ethers.parseEther("1000")
    );
    console.log("MINTR module deployed at:", await mintrModule.getAddress());
  });

  it("should install a module in Kernel", async function () {
    // Define the keycode as bytes5 using hexlify
    const mintrKeycode = ethers
      .hexlify(ethers.toUtf8Bytes("MINTR"))
      .slice(0, 12); // bytes5 is 10 hex characters

    // Install the MINTR module in the Kernel
    await kernel.executeAction(0, await mintrModule.getAddress(), "0x"); // 0 = InstallModule
    const mintrAddress = await kernel.getModuleForKeycode(mintrKeycode); // Keycode is bytes5

    expect(mintrAddress).to.equal(await mintrModule.getAddress());
  });
  it("should set module permissions correctly", async function () {
    const mintrKeycode = ethers
      .hexlify(ethers.toUtf8Bytes("MINTR"))
      .slice(0, 12); // Convert string to bytes5
    const mintSelector = mintrModule.interface.getFunction("mint").selector;

    // Install the MINTR module in the Kernel
    await kernel.executeAction(0, await mintrModule.getAddress(), "0x"); // 0 = InstallModule
    await kernel.getModuleForKeycode(mintrKeycode); // Keycode is bytes5

    console.log("TEST: MINTR Keycode:", mintrKeycode); // Log keycode
    console.log("TEST: Mint Selector:", mintSelector); // Log function selector

    // Set permission in Kernel using the correct keycode
    await kernel.setModulePermission(
      await mintrModule.getAddress(), // MINTR module
      addr1.address, // The policy being granted permission
      mintSelector, // Mint function selector
      true // Grant permission
    );

    // Check if the permission was correctly set
    const hasPermission = await kernel.modulePermissions(
      mintrKeycode, // Ensure proper keycode format (bytes5)
      addr1.address,
      mintSelector
    );
    console.log("Has Permission:", hasPermission); // Log the result for debugging
    expect(hasPermission).to.be.true;
  });

  it("should revoke permissions correctly", async function () {
    const mintrKeycode = ethers
      .hexlify(ethers.toUtf8Bytes("MINTR"))
      .slice(0, 12); // Convert string to bytes5
    const mintSelector = mintrModule.interface.getFunction("mint").selector;

    // Install the MINTR module in the Kernel
    await kernel.executeAction(0, await mintrModule.getAddress(), "0x"); // 0 = InstallModule
    await kernel.getModuleForKeycode(mintrKeycode); // Keycode is bytes5

    // Grant permission first
    await kernel.setModulePermission(
      await mintrModule.getAddress(),
      addr1.address,
      mintSelector,
      true
    );

    // Revoke permission
    await kernel.setModulePermission(
      await mintrModule.getAddress(),
      addr1.address,
      mintSelector,
      false
    );

    const hasPermission = await kernel.modulePermissions(
      mintrKeycode,
      addr1.address,
      mintSelector
    );
    expect(hasPermission).to.be.false;
  });
});
