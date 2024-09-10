import { expect } from "chai";
import pkg from "hardhat";
const { ethers } = pkg;

describe("Staking", function () {
  let stakingRewards, debaseToken, user1, owner;

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
      ethers.parseEther("1000000")
    );

    // Deploy Staking Contract
    const Staking = await ethers.getContractFactory("STAKE");
    stakingRewards = await Staking.deploy(owner.address, debaseToken.address);
  });

  it("Should allow staking tokens", async function () {
    const stakeAmount = ethers.parseEther("1000");

    await debaseToken.mint(user1.address, stakeAmount);
    await debaseToken
      .connect(user1)
      .approve(stakingRewards.address, stakeAmount);
    await stakingRewards.connect(user1).stake(stakeAmount);

    expect(await stakingRewards.stakedBalance(user1.address)).to.equal(
      stakeAmount
    );
  });

  // Add more staking related tests here
});
