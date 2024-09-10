import { expect } from "chai";
import pkg from "hardhat";
import { deployContracts } from "./helpers/setup.js";
const { ethers } = pkg;

describe("BOND", function () {
  let debase, stake, bond, controller, policyContract, owner, addr1, addr2;

  beforeEach(async function () {
    ({ debase, stake, bond, controller, policyContract, owner, addr1, addr2 } =
      await deployContracts());

    // Mint tokens for addr1 and addr2
    await debase.mint(addr1.address, ethers.parseEther("1000000"));
    await debase.mint(addr2.address, ethers.parseEther("1000000"));
  });

  describe("Bond Creation", function () {
    it("Should create a bond correctly", async function () {
      await debase
        .connect(addr1)
        .approve(controller.getAddress(), ethers.parseEther("100"));
      await controller
        .connect(addr1)
        .createBond(addr1.address, ethers.parseEther("100"), false);
      const userBond = await bond.bonds(addr1.address);
      expect(userBond.payout).to.equal(ethers.parseEther("115")); // 100 + 15% discount
    });

    it("Should create a partner bond with higher discount", async function () {
      await debase
        .connect(addr1)
        .approve(controller.getAddress(), ethers.parseEther("100"));
      await controller
        .connect(addr1)
        .createBond(addr1.address, ethers.parseEther("100"), true);
      const userBond = await bond.bonds(addr1.address);
      expect(userBond.payout).to.equal(ethers.parseEther("125")); // 100 + 25% discount
    });
  });

  describe("Bond Redemption", function () {
    beforeEach(async function () {
      await debase
        .connect(addr1)
        .approve(controller.getAddress(), ethers.parseEther("100"));
      await controller
        .connect(addr1)
        .createBond(addr1.address, ethers.parseEther("100"), false);
    });

    it("Should not allow redeeming an immature bond", async function () {
      await expect(
        controller.connect(addr1).redeemBond(addr1.address)
      ).to.be.revertedWith("Bond not yet matured");
    });

    it("Should allow redeeming a mature bond", async function () {
      await ethers.provider.send("evm_increaseTime", [3 * 24 * 60 * 60]); // 3 days
      await ethers.provider.send("evm_mine");
      const initialBalance = await debase.balanceOf(addr1.address);
      await controller.connect(addr1).redeemBond(addr1.address);
      const finalBalance = await debase.balanceOf(addr1.address);
      expect(finalBalance).to.be.gt(initialBalance);
    });
  });
  describe("Discount Settings", function () {
    it("Should allow setting new discounts", async function () {
      await controller.connect(owner).setBondingDiscount(false, 2000); // 20% in basis points
      await debase
        .connect(addr1)
        .approve(controller.getAddress(), ethers.parseEther("100"));
      await controller
        .connect(addr1)
        .createBond(addr1.address, ethers.parseEther("100"), false);
      const userBond = await bond.bonds(addr1.address);
      expect(userBond.payout).to.equal(ethers.parseEther("120")); // 100 + 20% discount
    });

    it("Should not allow setting discounts higher than 50%", async function () {
      await expect(controller.connect(owner).setBondingDiscount(false, 5100))
        .to.be.revertedWithCustomError(bond, "DiscountTooHigh")
        .withArgs(5100);
    });
  });
});
