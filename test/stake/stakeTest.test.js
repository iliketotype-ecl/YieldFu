import { expect } from "chai";
import pkg from "hardhat";
const { ethers } = pkg;
import { deployContracts } from "../setup/deployContracts.test.js";

describe("STAKE Module Tests using StakingPolicy", function () {
  let kernel, yieldFuToken, stakeModule, stakingPolicy, owner, addr1, addr2;
  const initialSupply = ethers.parseEther("1000000");
  const dailyMintCap = ethers.parseEther("100000");
  const debaseRate = 300; // 3% debasement
  const debaseInterval = 86400; // 1 day
  const minDebaseThreshold = ethers.parseEther("500000");
  const baseAPY = 100000; // 1000%
  const boostedAPY = 500000; // 5000%
  const cooldownPeriod = 86400 * 3; // 3 days
  const earlyUnstakeSlashRate = 500; // 5%
  const maxStakeCap = ethers.parseEther("500000");

  beforeEach(async function () {
    const contracts = await deployContracts({
      initialSupply,
      dailyMintCap,
      debaseRate,
      debaseInterval,
      minDebaseThreshold,
      baseAPY,
      boostedAPY,
      cooldownPeriod,
      earlyUnstakeSlashRate,
      maxStakeCap,
    });

    ({ kernel, yieldFuToken, stakeModule, stakingPolicy, owner, addr1, addr2 } =
      contracts);
  });

  it("should allow staking tokens", async function () {
    const stakeAmount = ethers.parseEther("100");

    await yieldFuToken.transfer(addr1.address, stakeAmount);
    await yieldFuToken
      .connect(addr1)
      .approve(await stakeModule.getAddress(), stakeAmount);

    await stakingPolicy.connect(addr1).stake(stakeAmount);

    const stakeInfo = await stakeModule.getStakeInfo(addr1.address);
    expect(stakeInfo.stakedAmount).to.equal(stakeAmount);
    expect(stakeInfo.pendingRewards).to.equal(0);
  });

  it("should reject staking more than the max stake cap", async function () {
    const stakeAmount = ethers.parseEther("600000"); // Above the max cap
    await yieldFuToken.transfer(addr1.address, stakeAmount);
    await yieldFuToken
      .connect(addr1)
      .approve(await stakeModule.getAddress(), stakeAmount);

    await expect(
      stakingPolicy.connect(addr1).stake(stakeAmount)
    ).to.be.revertedWithCustomError(stakeModule, "STAKE_MaxStakeCapExceeded");
  });

  it("should allow unstaking tokens after cooldown", async function () {
    const stakeAmount = ethers.parseEther("100");

    await yieldFuToken.transfer(addr1.address, stakeAmount);
    await yieldFuToken
      .connect(addr1)
      .approve(await stakeModule.getAddress(), stakeAmount);
    await stakingPolicy.connect(addr1).stake(stakeAmount);

    await ethers.provider.send("evm_increaseTime", [cooldownPeriod]);
    await ethers.provider.send("evm_mine");

    await stakingPolicy.connect(addr1).unstake(stakeAmount);

    const stakeInfo = await stakeModule.getStakeInfo(addr1.address);
    expect(stakeInfo.stakedAmount).to.equal(0);
  });

  it("should slash early unstake", async function () {
    const stakeAmount = ethers.parseEther("100");

    await yieldFuToken.transfer(addr1.address, stakeAmount);
    await yieldFuToken
      .connect(addr1)
      .approve(await stakeModule.getAddress(), stakeAmount);
    await stakingPolicy.connect(addr1).stake(stakeAmount);

    await stakingPolicy.connect(addr1).unstake(stakeAmount);

    const expectedTransferAmount = (stakeAmount * BigInt(9500)) / BigInt(10000); // 5% slashed
    const balance = await yieldFuToken.balanceOf(addr1.address);

    expect(balance).to.equal(expectedTransferAmount);
  });

  it("should update APY and apply boosted APY", async function () {
    const stakeAmount = ethers.parseEther("100");

    await yieldFuToken.transfer(addr1.address, stakeAmount);
    await yieldFuToken
      .connect(addr1)
      .approve(await stakeModule.getAddress(), stakeAmount);
    await stakingPolicy.connect(addr1).stake(stakeAmount);

    const boostDuration = 86400 * 30; // 30 days
    await stakingPolicy.connect(owner).boostAPY(boostDuration);

    await ethers.provider.send("evm_increaseTime", [boostDuration]);
    await ethers.provider.send("evm_mine");

    const stakeInfo = await stakeModule.getStakeInfo(addr1.address);
    const expectedBoostedReward =
      (stakeAmount * BigInt(boostedAPY) * BigInt(boostDuration)) /
      BigInt(365 * 86400 * 10000);

    expect(stakeInfo.pendingRewards).to.be.closeTo(
      expectedBoostedReward,
      ethers.parseEther("0.1")
    );
  });

  it("should allow claiming rewards", async function () {
    const stakeAmount = ethers.parseEther("100");

    // Transfer tokens to addr1 and approve the stakeModule to spend tokens
    await yieldFuToken.transfer(addr1.address, stakeAmount);
    await yieldFuToken
      .connect(addr1)
      .approve(await stakeModule.getAddress(), stakeAmount);

    // Stake the tokens via the stakingPolicy
    await stakingPolicy.connect(addr1).stake(stakeAmount);

    // Simulate a time period of 30 days to accumulate rewards
    const rewardPeriod = 86400 * 30; // 30 days
    await ethers.provider.send("evm_increaseTime", [rewardPeriod]);
    await ethers.provider.send("evm_mine");

    // Check pending rewards before claiming using the earned function
    const pendingRewards = await stakeModule.earned(addr1.address);
    console.log("Pending rewards before claiming:", pendingRewards.toString());

    // Ensure pending rewards are non-zero
    expect(pendingRewards).to.be.gt(0);

    // Get the balance of addr1 before claiming rewards
    const balanceBefore = await yieldFuToken.balanceOf(addr1.address);
    console.log("Balance before claiming rewards:", balanceBefore.toString());

    // Call claimReward via stakingPolicy to claim rewards
    await stakingPolicy.connect(addr1).claimReward();

    // Get the balance of addr1 after claiming rewards
    const balanceAfter = await yieldFuToken.balanceOf(addr1.address);
    console.log("Balance after claiming rewards:", balanceAfter.toString());

    // Ensure the balance after claiming is greater than before (rewards minted)
    expect(balanceAfter).to.be.gt(balanceBefore);

    // Check the stake info to ensure the pending rewards have been reset to 0
    const stakeInfo = await stakeModule.getStakeInfo(addr1.address);
    console.log("Stake info after claiming rewards:", stakeInfo);

    // Ensure that the pending rewards are zero after claiming
    expect(stakeInfo.pendingRewards).to.equal(0);
  });
});
