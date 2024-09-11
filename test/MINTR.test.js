import { expect } from "chai";
import pkg from "hardhat";
const { ethers } = pkg;

describe("Minting", function () {
  it("Should allow addresses with MINTER_ROLE to mint tokens", async function () {
    const mintAmount = ethers.parseEther("1000");

    // Mint new tokens from minter to user1
    await yieldFuToken.connect(minter).mint(user1.address, mintAmount);

    // Check the balance of user1 after minting
    expect(await yieldFuToken.balanceOf(user1.address)).to.equal(mintAmount);

    // Check the total supply after minting
    const totalSupply = ethers.parseEther("1000000").add(mintAmount);
    expect(await yieldFuToken.totalSupply()).to.equal(totalSupply);
  });

  it("Should not allow addresses without MINTER_ROLE to mint tokens", async function () {
    const mintAmount = ethers.parseEther("1000");

    // Try to mint from an address without MINTER_ROLE (burner in this case)
    await expect(
      yieldFuToken.connect(burner).mint(user1.address, mintAmount)
    ).to.be.revertedWith("AccessControl: account"); // reverts with AccessControl error
  });
});
