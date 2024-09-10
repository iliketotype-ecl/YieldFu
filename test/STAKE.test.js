import { expect } from "chai";
import { deployContracts } from "./helpers/setup.js";
import pkg from "hardhat";
const { ethers } = pkg;

describe("STAKE", function () {
  let debase, stake, bond, controller, policyContract, owner, addr1, addr2;

  beforeEach(async function () {
    ({ debase, stake, bond, controller, policyContract, owner, addr1, addr2 } =
      await deployContracts());
    await debase.mint(addr1.address, ethers.parseEther("1000000"));
    await debase.mint(addr2.address, ethers.parseEther("1000000"));
  });

  describe("Staking", function () {
    it("Should allow staking tokens", async function () {
      const { debase, stake, controller, addr1 } = await deployContracts();
      await debase.mint(addr1.address, ethers.parseEther("100"));
      await debase
        .connect(addr1)
        .approve(controller.getAddress(), ethers.parseEther("100"));
      await controller
        .connect(addr1)
        .stake(addr1.address, ethers.parseEther("100"));
      const userStake = await stake.stakes(addr1.address);
      expect(userStake.amount).to.equal(ethers.parseEther("100"));
    });

    it("Should allow unstaking tokens", async function () {
      await debase.approve(stake.getAddress(), ethers.parseEther("100"));
      await stake.stake(owner.address, ethers.parseEther("100"));
      await stake.unstake(owner.address, ethers.parseEther("50"));
      const userStake = await stake.stakes(owner.address);
      expect(userStake.amount).to.equal(ethers.parseEther("50"));
    });
  });

  describe("Rewards", function () {
    it("Should allow claiming rewards", async function () {
      await debase.mint(stake.getAddress(), ethers.parseEther("1000000"));
      await controller
        .connect(addr1)
        .stake(addr1.address, ethers.parseEther("100"));
      await ethers.provider.send("evm_increaseTime", [86400]); // 1 day
      await ethers.provider.send("evm_mine");
      const initialBalance = await debase.balanceOf(addr1.address);
      await controller.connect(addr1).claimReward(addr1.address);
      const finalBalance = await debase.balanceOf(addr1.address);
      expect(finalBalance).to.be.gt(initialBalance);
    });
  });

  describe("APY Settings", function () {
    it("Should allow setting new APY rates", async function () {
      await stake.setAPY(1500, 3000); // 15% base APY, 30% boost APY
      // You might want to add more assertions here to check if the new rates are applied correctly
    });
  });

  describe("Boost Activation", function () {
    it("Should allow activating boost", async function () {
      const boostDuration = 7 * 24 * 60 * 60; // 7 days
      await stake.activateBoost(boostDuration);
      // You might want to add more assertions here to check if the boost is activated correctly
    });
  });
});
