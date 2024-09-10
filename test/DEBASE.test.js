import { expect } from "chai";
import pkg from "hardhat";
const { ethers } = pkg;

describe("DEBASE Token", function () {
  let debaseToken, owner, user1;

  const INITIAL_SUPPLY = ethers.parseEther("1000000");

  before(async function () {
    [owner, user1] = await ethers.getSigners();
  });

  beforeEach(async function () {
    // Deploy DEBASE Token
    const DebaseToken = await ethers.getContractFactory("DEBASE");
    debaseToken = await DebaseToken.deploy(
      owner.address,
      "DebaseToken",
      "DBT",
      INITIAL_SUPPLY
    );
  });

  it("Should mint tokens to user1", async function () {
    const mintAmount = ethers.parseEther("1000");
    await debaseToken.mint(user1.address, mintAmount);
    expect(await debaseToken.balanceOf(user1.address)).to.equal(mintAmount);
  });

  it("Should burn tokens from user1", async function () {
    const mintAmount = ethers.parseEther("1000");
    const burnAmount = ethers.parseEther("500");

    // Mint tokens first
    await debaseToken.mint(user1.address, mintAmount);

    // Burn tokens
    await debaseToken.burnFrom(user1.address, burnAmount);
    expect(await debaseToken.balanceOf(user1.address)).to.equal(
      ethers.parseEther("500")
    );
  });

  // Add more DEBASE Token related tests here
});
