import { expect } from "chai";
import pkg from "hardhat";
const { ethers } = pkg;

describe("MINTR", function () {
  let mintr, debaseToken, policy, user1, owner;

  before(async function () {
    [owner, policy, user1] = await ethers.getSigners();
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

    // Deploy MINTR Contract
    const Mintr = await ethers.getContractFactory("MINTR");
    mintr = await Mintr.deploy(debaseToken.address);
  });

  it("Should allow minting tokens", async function () {
    const mintAmount = ethers.parseEther("100");

    await mintr.increaseMintApproval(policy.address, mintAmount);
    await mintr.connect(policy).mint(user1.address, mintAmount);

    expect(await debaseToken.balanceOf(user1.address)).to.equal(mintAmount);
  });

  it("Should allow burning tokens", async function () {
    const mintAmount = ethers.parseEther("100");
    const burnAmount = ethers.parseEther("50");

    await mintr.increaseMintApproval(policy.address, mintAmount);
    await mintr.connect(policy).mint(user1.address, mintAmount);

    await mintr.connect(policy).burn(user1.address, burnAmount);

    expect(await debaseToken.balanceOf(user1.address)).to.equal(
      ethers.parseEther("50")
    );
  });

  // Add more MINTR related tests here
});
