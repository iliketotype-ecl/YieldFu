import { expect } from "chai";
import pkg from "hardhat";
const { ethers } = pkg;

describe("Bonding", function () {
  let bonding, debaseToken, user1, owner, treasury;

  before(async function () {
    [owner, user1, treasury] = await ethers.getSigners();
  });

  beforeEach(async function () {
    // Deploy DEBASE Token
    const DebaseToken = await ethers.getContractFactory("DEBASE");
    debaseToken = await DebaseToken.deploy(
      owner.address,
      "DebaseToken",
      "DBT",
      ethers.parseEther("1000000")
    );

    // Deploy Bonding Contract
    const Bonding = await ethers.getContractFactory("BOND");
    bonding = await Bonding.deploy(
      owner.address,
      debaseToken.address,
      treasury.address
    );
  });

  it("Should allow bonding ETH and return payout", async function () {
    const bondAmount = ethers.parseEther("1");

    // Perform bond operation
    await bonding.connect(user1).bondEth({ value: bondAmount });

    // Fetch bond details
    const bond = await bonding.bonds(user1.address);

    expect(bond.payout).to.be.gt(bondAmount);
  });

  it("Should allow claiming bonds", async function () {
    const bondAmount = ethers.parseEther("1");

    // Perform bond operation
    await bonding.connect(user1).bondEth({ value: bondAmount });

    // Fast forward time or manipulate bond maturity time if needed
    await ethers.provider.send("evm_increaseTime", [60 * 60 * 24]); // Move 1 day forward
    await ethers.provider.send("evm_mine");

    // Claim bond
    await bonding.connect(user1).claim();
    const userBalance = await debaseToken.balanceOf(user1.address);

    expect(userBalance).to.be.gt(0);
  });

  it("Should not allow claiming bonds before maturity", async function () {
    const bondAmount = ethers.parseEther("1");

    // Perform bond operation
    await bonding.connect(user1).bondEth({ value: bondAmount });

    // Try to claim bond before maturity
    await expect(bonding.connect(user1).claim()).to.be.revertedWith(
      "Bond not mature yet"
    );
  });

  it("Should allow checking bond details", async function () {
    const bondAmount = ethers.parseEther("1");

    // Perform bond operation
    await bonding.connect(user1).bondEth({ value: bondAmount });

    // Fetch bond details
    const bond = await bonding.bonds(user1.address);

    expect(bond.payout).to.be.gt(bondAmount);
    expect(bond.lastBlock).to.be.gt(0);
    expect(bond.maturity).to.be.gt(0);
  });

  // Add more bonding tests as needed
});
