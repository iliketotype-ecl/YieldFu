import { expect } from "chai";
import { deployContracts } from "./helpers/setup.js";
import pkg from "hardhat";
const { ethers } = pkg;

describe("DEBASE", function () {
  let debase, stake, bond, controller, policyContract, owner, addr1, addr2;

  beforeEach(async function () {
    ({ debase, stake, bond, controller, policyContract, owner, addr1, addr2 } =
      await deployContracts());
    await debase.mint(
      await controller.getAddress(),
      ethers.parseEther("2000000")
    ); // Mint tokens to the controller
  });

  describe("Deployment", function () {
    it("Should set the right owner", async function () {
      expect(
        await debase.hasRole(await debase.DEFAULT_ADMIN_ROLE(), owner.address)
      ).to.equal(true);
    });

    it("Should assign the total supply of tokens to the owner", async function () {
      const totalSupply = await debase.totalSupply();
      expect(totalSupply).to.equal(ethers.parseEther("9000000")); // 1M owner + 1M debase + 1M controller
    });
  });

  describe("Transactions", function () {
    it("Should transfer tokens between accounts", async function () {
      await debase.transfer(addr1.address, ethers.parseEther("50"));
      const addr1Balance = await debase.balanceOf(addr1.address);
      expect(addr1Balance).to.equal(ethers.parseEther("50"));

      await debase
        .connect(addr1)
        .transfer(addr2.address, ethers.parseEther("50"));
      const addr2Balance = await debase.balanceOf(addr2.address);
      expect(addr2Balance).to.equal(ethers.parseEther("50"));
    });

    it("Should fail if sender doesn't have enough tokens", async function () {
      const initialOwnerBalance = await debase.balanceOf(owner.address);
      await expect(
        debase
          .connect(addr1)
          .transfer(owner.address, ethers.parseEther("2000000"))
      ).to.be.revertedWithCustomError(debase, "ERC20InsufficientBalance");
      expect(await debase.balanceOf(owner.address)).to.equal(
        initialOwnerBalance
      );
    });
  });

  describe("Rebasing", function () {
    it("Should rebase tokens correctly", async function () {
      const initialSupply = await debase.totalSupply();
      console.log("Initial Total Supply:", initialSupply.toString());

      const controllerBalance = await debase.balanceOf(
        await controller.getAddress()
      );
      console.log("Initial Controller Balance:", controllerBalance.toString());

      await ethers.provider.send("evm_increaseTime", [86400]); // Advance time by 1 day
      await ethers.provider.send("evm_mine"); // Mine a block after time increase

      await controller.connect(owner).debase();

      const newSupply = await debase.totalSupply();
      console.log("New Total Supply:", newSupply.toString());

      const newControllerBalance = await debase.balanceOf(
        await controller.getAddress()
      );
      console.log("New Controller Balance:", newControllerBalance.toString());

      expect(newSupply).to.be.lt(initialSupply);
      expect(newControllerBalance).to.be.lt(controllerBalance);

      // Check if the reduction is approximately 3% (allowing for some rounding errors)
      const expectedNewSupply = initialSupply.mul(9700).div(10000);
      expect(newSupply).to.be.closeTo(
        expectedNewSupply,
        ethers.parseEther("1")
      ); // Allow 1 token difference for rounding
    });

    it("Should not allow rebasing more than once per day", async function () {
      await controller.connect(owner).debase(); // First rebase

      // Try to rebase again without advancing time
      await expect(controller.connect(owner).debase()).to.be.revertedWith(
        "Cannot rebase yet"
      );
    });
  });
});
