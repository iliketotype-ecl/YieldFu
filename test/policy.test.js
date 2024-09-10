import { expect } from "chai";
import { deployContracts } from "./helpers/setup.js";
import pkg from "hardhat";
const { ethers } = pkg;

describe("ctrl", function () {
  let debase, stake, bond, controller, policyContract, owner, addr1, addr2;

  beforeEach(async function () {
    ({ debase, stake, bond, controller, policyContract, owner, addr1, addr2 } =
      await deployContracts());
    await debase.mint(addr1.address, ethers.parseEther("1000000"));
    await debase.mint(addr2.address, ethers.parseEther("1000000"));
  });

  describe("Token Operations", function () {
    it("Should mint tokens", async function () {
      await controller
        .connect(addr1)
        .mint(addr2.address, ethers.parseEther("100"));
      expect(await debase.balanceOf(addr2.address)).to.equal(
        ethers.parseEther("100")
      );
    });

    it("Should burn tokens", async function () {
      await controller
        .connect(addr1)
        .mint(addr2.address, ethers.parseEther("100"));
      await debase
        .connect(addr2)
        .approve(controller.getAddress(), ethers.parseEther("50"));
      await controller
        .connect(addr1)
        .burn(addr2.address, ethers.parseEther("50"));
      expect(await debase.balanceOf(addr2.address)).to.equal(
        ethers.parseEther("50")
      );
    });

    it("Should rebase tokens", async function () {
      const initialSupply = await debase.totalSupply();
      await controller.connect(addr1).debase();
      const newSupply = await debase.totalSupply();
      expect(newSupply).to.be.lt(initialSupply);
    });
  });

  describe("Staking Operations", function () {
    it("Should allow staking", async function () {
      await controller
        .connect(addr1)
        .mint(addr2.address, ethers.parseEther("100"));
      await debase
        .connect(addr2)
        .approve(controller.getAddress(), ethers.parseEther("100"));
      await controller
        .connect(addr2)
        .stake(addr2.address, ethers.parseEther("100"));
      const userStake = await stake.stakes(addr2.address);
      expect(userStake.amount).to.equal(ethers.parseEther("100"));
    });

    it("Should allow unstaking", async function () {
      await controller
        .connect(addr1)
        .mint(addr2.address, ethers.parseEther("100"));
      await debase
        .connect(addr2)
        .approve(controller.getAddress(), ethers.parseEther("100"));
      await controller
        .connect(addr2)
        .stake(addr2.address, ethers.parseEther("100"));
      await controller
        .connect(addr2)
        .unstake(addr2.address, ethers.parseEther("50"));
      const userStake = await stake.stakes(addr2.address);
      expect(userStake.amount).to.equal(ethers.parseEther("50"));
    });
  });

  describe("Bonding Operations", function () {
    it("Should create a bond", async function () {
      await controller
        .connect(addr1)
        .mint(addr2.address, ethers.parseEther("100"));
      await debase
        .connect(addr2)
        .approve(controller.getAddress(), ethers.parseEther("100"));
      await controller
        .connect(addr2)
        .createBond(addr2.address, ethers.parseEther("100"), false);
      const userBond = await bond.bonds(addr2.address);
      expect(userBond.payout).to.equal(ethers.parseEther("115")); // 100 + 15% discount
    });

    it("Should redeem a mature bond", async function () {
      await controller
        .connect(addr1)
        .mint(addr2.address, ethers.parseEther("100"));
      await debase
        .connect(addr2)
        .approve(controller.getAddress(), ethers.parseEther("100"));
      await controller
        .connect(addr2)
        .createBond(addr2.address, ethers.parseEther("100"), false);

      // Fast forward time to make bond mature
      await ethers.provider.send("evm_increaseTime", [3 * 24 * 60 * 60]); // 3 days
      await ethers.provider.send("evm_mine");

      // Redeem bond
      await controller.connect(addr2).redeemBond(addr2.address);
      expect(await debase.balanceOf(addr2.address)).to.equal(
        ethers.parseEther("115")
      );
    });
  });

  describe("Policy Operations", function () {
    it("Should set staking APY", async function () {
      await controller.connect(owner).setStakingAPY(1500, 3000);
      // Add assertions to check if APY was set correctly
    });

    it("Should activate staking boost", async function () {
      await controller.connect(addr1).activateStakingBoost(7 * 24 * 60 * 60); // 7 days boost
      // Add assertions to check if boost was activated correctly
    });

    it("Should set bonding discount", async function () {
      await controller.connect(addr1).setBondingDiscount(false, 2000); // 20% discount for non-partner token
      // Add assertions to check if discount was set correctly
    });
  });
});
