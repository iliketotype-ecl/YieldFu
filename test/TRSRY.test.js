import { expect } from "chai";
import pkg from "hardhat";
const { ethers } = pkg;

describe("Treasury", function () {
  let treasuryModule, debaseToken, user1, owner, policy;

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

    // Deploy Treasury Module
    const TRSRY = await ethers.getContractFactory("TRSRY");
    treasuryModule = await TRSRY.deploy(owner.address);

    // Mint some tokens to the treasury
    await debaseToken.mint(treasuryModule.address, ethers.parseEther("10000"));
  });

  it("Should allow treasury withdrawals", async function () {
    const withdrawalAmount = ethers.parseEther("500");

    // Authorize withdrawal
    await treasuryModule.increaseWithdrawApproval(
      policy.address,
      debaseToken.address,
      withdrawalAmount
    );

    // Withdraw tokens from the treasury
    await treasuryModule
      .connect(policy)
      .withdrawReserves(user1.address, debaseToken.address, withdrawalAmount);

    expect(await debaseToken.balanceOf(user1.address)).to.equal(
      withdrawalAmount
    );
  });

  it("Should not allow unauthorized withdrawals", async function () {
    const withdrawalAmount = ethers.parseEther("500");

    // Attempt to withdraw without authorization
    await expect(
      treasuryModule
        .connect(user1)
        .withdrawReserves(user1.address, debaseToken.address, withdrawalAmount)
    ).to.be.revertedWith("TRSRY: Withdrawal not approved");
  });

  it("Should allow increasing debt approval", async function () {
    const debtAmount = ethers.parseEther("1000");

    // Authorize debt
    await treasuryModule.increaseDebtorApproval(
      policy.address,
      debaseToken.address,
      debtAmount
    );

    expect(
      await treasuryModule.debtApproval(policy.address, debaseToken.address)
    ).to.equal(debtAmount);
  });

  it("Should allow incurring debt", async function () {
    const debtAmount = ethers.parseEther("500");

    // Authorize and incur debt
    await treasuryModule.increaseDebtorApproval(
      policy.address,
      debaseToken.address,
      debtAmount
    );
    await treasuryModule
      .connect(policy)
      .incurDebt(debaseToken.address, debtAmount);

    expect(await treasuryModule.totalDebt(debaseToken.address)).to.equal(
      debtAmount
    );
    expect(
      await treasuryModule.reserveDebt(debaseToken.address, policy.address)
    ).to.equal(debtAmount);
  });

  it("Should allow repaying debt", async function () {
    const debtAmount = ethers.parseEther("500");

    // Authorize and incur debt
    await treasuryModule.increaseDebtorApproval(
      policy.address,
      debaseToken.address,
      debtAmount
    );
    await treasuryModule
      .connect(policy)
      .incurDebt(debaseToken.address, debtAmount);

    // Repay debt
    await treasuryModule
      .connect(policy)
      .repayDebt(policy.address, debaseToken.address, debtAmount);

    expect(await treasuryModule.totalDebt(debaseToken.address)).to.equal(0);
    expect(
      await treasuryModule.reserveDebt(debaseToken.address, policy.address)
    ).to.equal(0);
  });

  // Add more treasury-related tests as needed
});
