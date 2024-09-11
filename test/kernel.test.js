import { expect } from "chai";
import pkg from "hardhat";
const { ethers } = pkg;

describe("Kernel Deployment Debugging", function () {
  let Kernel;
  let kernel;
  let owner;

  beforeEach(async function () {
    // Get Contract Factories
    console.log("Getting contract factories...");
    Kernel = await ethers.getContractFactory("Kernel");

    // Get Signers
    console.log("Getting signers...");
    [owner] = await ethers.getSigners();
    console.log("Owner:", owner.address);

    // Deploy Kernel with debug logging
    console.log("Deploying Kernel...");
    try {
      kernel = await Kernel.deploy({ gasLimit: 10000000 }); // Increase gas limit
      await kernel.waitForDeployment();
      console.log("Kernel deployed at:", kernel.target); // Logging the deployed address
    } catch (error) {
      console.error("Kernel deployment failed with error:", error.message);
    }
  });

  describe("Deployment", function () {
    it("Should deploy Kernel successfully", async function () {
      expect(kernel.target).to.not.be.undefined;
      expect(kernel.target).to.not.be.null;
      expect(kernel.target).to.match(/^0x[0-9a-fA-F]{40}$/); // Check if valid address
    });
  });
});
