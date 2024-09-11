import { expect } from "chai";
import pkg from "hardhat";
const { ethers } = pkg;

// Define the Actions enum to match your Kernel contract
const Actions = {
  InstallModule: 0,
  UpgradeModule: 1,
  ActivatePolicy: 2,
  DeactivatePolicy: 3,
  ChangeExecutor: 4,
  MigrateKernel: 5,
  ExecuteAction: 6,
};

describe("Kernel and MINTR Module Integration", function () {
  let Kernel, YieldFuToken, MINTR, DEBASE, TokenPolicy;
  let kernel, yieldFuToken, mintrModule, debaseModule, tokenPolicy;
  let owner, minter, user1;
  let minterRoleHash;

  beforeEach(async function () {
    [owner, minter, user1] = await ethers.getSigners();
    Kernel = await ethers.getContractFactory("Kernel");
    YieldFuToken = await ethers.getContractFactory("YieldFuToken");
    MINTR = await ethers.getContractFactory("MINTR");
    DEBASE = await ethers.getContractFactory("DEBASE");
    TokenPolicy = await ethers.getContractFactory("TokenPolicy");

    // Deploy Kernel
    kernel = await Kernel.deploy();
    console.log("Kernel deployed at:", await kernel.getAddress());

    // Ensure the owner has the DEFAULT_ADMIN_ROLE
    const DEFAULT_ADMIN_ROLE = ethers.ZeroHash;
    await kernel.connect(owner).grantRole(DEFAULT_ADMIN_ROLE, owner.address);
    console.log(
      "Owner has DEFAULT_ADMIN_ROLE:",
      await kernel.hasRole(DEFAULT_ADMIN_ROLE, owner.address)
    );

    // Deploy YieldFuToken
    yieldFuToken = await YieldFuToken.deploy(
      "YieldFu",
      "YFU",
      ethers.parseEther("1000000"),
      owner.address
    );
    console.log("YieldFuToken deployed at:", await yieldFuToken.getAddress());

    // Deploy and Install MINTR module
    const initialDailyMintCap = ethers.parseEther("10000");
    mintrModule = await MINTR.deploy(
      await kernel.getAddress(),
      await yieldFuToken.getAddress(),
      initialDailyMintCap
    );
    console.log("MINTR module deployed at:", await mintrModule.getAddress());
    await kernel
      .connect(owner)
      .executeAction(0, await mintrModule.getAddress(), "0x");
    console.log("MINTR module installed in Kernel");

    // Deploy and Install DEBASE module
    const initialDebaseRate = 100; // 1% in basis points
    const initialDebaseInterval = 86400; // 1 day in seconds
    const initialMinDebaseThreshold = ethers.parseEther("50000");
    debaseModule = await DEBASE.deploy(
      await kernel.getAddress(),
      await yieldFuToken.getAddress(),
      initialDebaseRate,
      initialDebaseInterval,
      initialMinDebaseThreshold
    );
    console.log("DEBASE module deployed at:", await debaseModule.getAddress());
    await kernel
      .connect(owner)
      .executeAction(0, await debaseModule.getAddress(), "0x");
    console.log("DEBASE module installed in Kernel");

    // Deploy and Activate TokenPolicy
    tokenPolicy = await TokenPolicy.deploy(
      await kernel.getAddress(),
      await yieldFuToken.getAddress()
    );
    console.log("TokenPolicy deployed at:", await tokenPolicy.getAddress());
    await kernel
      .connect(owner)
      .executeAction(2, await tokenPolicy.getAddress(), "0x");
    console.log("TokenPolicy activated in Kernel");

    // Grant permissions and roles
    minterRoleHash = await yieldFuToken.MINTER_ROLE();
    await yieldFuToken.connect(owner).grantRole(minterRoleHash, minter.address);
    console.log(
      "Minter granted MINTER_ROLE in YieldFuToken:",
      await yieldFuToken.hasRole(minterRoleHash, minter.address)
    );

    // Grant MINTER_ROLE to TokenPolicy in YieldFuToken
    await yieldFuToken
      .connect(owner)
      .grantRole(minterRoleHash, await tokenPolicy.getAddress());
    console.log(
      "TokenPolicy granted MINTER_ROLE in YieldFuToken:",
      await yieldFuToken.hasRole(minterRoleHash, await tokenPolicy.getAddress())
    );

    // Grant MINTER_ROLE to MINTR module in YieldFuToken
    await yieldFuToken
      .connect(owner)
      .grantRole(minterRoleHash, await mintrModule.getAddress());
    console.log(
      "MINTR module granted MINTER_ROLE in YieldFuToken:",
      await yieldFuToken.hasRole(minterRoleHash, await mintrModule.getAddress())
    );

    // Use getFunction('functionName').selector to retrieve the correct selectors
    const addMinterSelector =
      mintrModule.interface.getFunction("addMinter").selector;
    const mintSelector = mintrModule.interface.getFunction("mint").selector;
    const debaseSelector =
      debaseModule.interface.getFunction("debase").selector;

    // Set module permissions in Kernel
    await kernel
      .connect(owner)
      .setModulePermission(
        await debaseModule.getAddress(),
        await tokenPolicy.getAddress(),
        debaseSelector,
        true
      );
    await kernel
      .connect(owner)
      .setModulePermission(
        await mintrModule.getAddress(),
        owner.address,
        addMinterSelector,
        true
      );
    await kernel
      .connect(owner)
      .setModulePermission(
        await mintrModule.getAddress(),
        await tokenPolicy.getAddress(),
        mintSelector,
        true
      );
    await kernel
      .connect(owner)
      .setModulePermission(
        await mintrModule.getAddress(),
        minter.address,
        mintSelector,
        true
      );

    console.log("Permissions set for addMinter, mint, and debase functions");

    // Register the TokenPolicy in the MINTR module
    await mintrModule
      .connect(owner)
      .addMinter(await tokenPolicy.getAddress(), ethers.parseEther("10000"));
    console.log(
      "TokenPolicy registered in MINTR module:",
      await mintrModule.isMinter(await tokenPolicy.getAddress())
    );

    // Verify final permissions
    console.log("Final permission check:");
    console.log(
      "- Minter has MINTER_ROLE in YieldFuToken:",
      await yieldFuToken.hasRole(minterRoleHash, minter.address)
    );
    console.log(
      "- TokenPolicy has MINTER_ROLE in YieldFuToken:",
      await yieldFuToken.hasRole(minterRoleHash, await tokenPolicy.getAddress())
    );
    console.log(
      "- MINTR module has MINTER_ROLE in YieldFuToken:",
      await yieldFuToken.hasRole(minterRoleHash, await mintrModule.getAddress())
    );
    console.log(
      "- TokenPolicy has mint permission in Kernel:",
      await kernel.modulePermissions(
        await mintrModule.KEYCODE(),
        await tokenPolicy.getAddress(),
        mintSelector
      )
    );
    console.log(
      "- Minter has mint permission in Kernel:",
      await kernel.modulePermissions(
        await mintrModule.KEYCODE(),
        minter.address,
        mintSelector
      )
    );
    console.log(
      "- TokenPolicy is registered in MINTR:",
      await mintrModule.isMinter(await tokenPolicy.getAddress())
    );
    console.log(
      "- TokenPolicy has debase permission in Kernel:",
      await kernel.modulePermissions(
        await debaseModule.KEYCODE(),
        await tokenPolicy.getAddress(),
        debaseSelector
      )
    );

    const tokenPolicyInfo = await mintrModule.getMinterInfo(
      await tokenPolicy.getAddress()
    );
    console.log("TokenPolicy minter info:");
    console.log("- Is active:", tokenPolicyInfo.isActive);
    console.log("- Mint limit:", tokenPolicyInfo.mintLimit.toString());
    console.log("- Minted amount:", tokenPolicyInfo.mintedAmount.toString());
  });

  describe("MINTR Module", function () {
    it("Should allow authorized minters to mint tokens", async function () {
      const mintAmount = ethers.parseEther("100");
      const initialBalance = await yieldFuToken.balanceOf(user1.address);
      console.log("Initial Balance of user1:", initialBalance.toString());

      // Log relevant information
      console.log("Minter address:", minter.address);
      console.log("TokenPolicy address:", await tokenPolicy.getAddress());
      console.log("MINTR module address:", await mintrModule.getAddress());

      // Verify minter's permissions again
      console.log(
        "Minter has MINTER_ROLE in YieldFuToken:",
        await yieldFuToken.hasRole(minterRoleHash, minter.address)
      );
      console.log(
        "TokenPolicy has MINTER_ROLE in YieldFuToken:",
        await yieldFuToken.hasRole(
          minterRoleHash,
          await tokenPolicy.getAddress()
        )
      );
      console.log(
        "MINTR module has MINTER_ROLE in YieldFuToken:",
        await yieldFuToken.hasRole(
          minterRoleHash,
          await mintrModule.getAddress()
        )
      );
      const mintSelector = mintrModule.interface.getFunction("mint").selector;
      console.log(
        "Minter has mint permission in Kernel:",
        await kernel.modulePermissions(
          await mintrModule.KEYCODE(),
          minter.address,
          mintSelector
        )
      );
      console.log(
        "TokenPolicy has mint permission in Kernel:",
        await kernel.modulePermissions(
          await mintrModule.KEYCODE(),
          await tokenPolicy.getAddress(),
          mintSelector
        )
      );
      console.log(
        "TokenPolicy is registered in MINTR:",
        await mintrModule.isMinter(await tokenPolicy.getAddress())
      );

      // Log MINTR module state before minting
      console.log("MINTR module state before minting:");
      console.log(
        "Daily mint cap:",
        (await mintrModule.dailyMintCap()).toString()
      );
      console.log(
        "Minted today:",
        (await mintrModule.mintedToday()).toString()
      );
      console.log(
        "Last mint day:",
        (await mintrModule.lastMintDay()).toString()
      );

      // Attempt to mint tokens
      try {
        console.log("Test: Attempting to mint tokens");
        const tx = await tokenPolicy
          .connect(minter)
          .mint(user1.address, mintAmount);
        const receipt = await tx.wait();
        console.log("Test: Minting transaction completed");
        console.log("Gas used:", receipt.gasUsed.toString());

        // Log MINTR module state after minting
        console.log("MINTR module state after minting:");
        console.log(
          "Daily mint cap:",
          (await mintrModule.dailyMintCap()).toString()
        );
        console.log(
          "Minted today:",
          (await mintrModule.mintedToday()).toString()
        );
        console.log(
          "Last mint day:",
          (await mintrModule.lastMintDay()).toString()
        );
      } catch (error) {
        console.error("Test: Minting failed with error:", error.message);
        if (error.errorName) {
          console.error("Test: Custom error name:", error.errorName);
          console.error("Test: Custom error args:", error.errorArgs);
        }
        console.error("Test: Error stack trace:", error.stack);
        throw error;
      }

      const finalBalance = await yieldFuToken.balanceOf(user1.address);
      console.log("Final Balance of user1:", finalBalance.toString());
      expect(finalBalance).to.equal(initialBalance + mintAmount);
    });

    it("Should respect the daily mint cap", async function () {
      const mintAmount = ethers.parseEther("20000"); // Exceeds the cap
      const initialBalance = await yieldFuToken.balanceOf(user1.address);
      console.log("Initial Balance of user1:", initialBalance.toString());

      // Minting over the daily cap should fail
      await expect(
        tokenPolicy.connect(minter).mint(user1.address, mintAmount)
      ).to.be.revertedWithCustomError(mintrModule, "MINTR_DailyCapExceeded");

      const finalBalance = await yieldFuToken.balanceOf(user1.address);
      console.log(
        "Final Balance of user1 after daily cap exceeded:",
        finalBalance.toString()
      );
      expect(finalBalance).to.equal(initialBalance);
    });
  });

  describe("DEBASE Module", function () {
    it("Should debase token supply after the interval", async function () {
      // Mint some tokens to ensure we're above the minimum threshold
      const mintAmount = ethers.parseEther("100000");
      await mintrModule
        .connect(owner)
        .addMinter(owner.address, ethers.parseEther("1000000"));
      await mintrModule
        .connect(owner)
        .mint(owner.address, owner.address, mintAmount);

      const totalSupplyBefore = await yieldFuToken.totalSupply();
      console.log("Total Supply before debase:", totalSupplyBefore.toString());

      // Fast-forward time by the debase interval
      await ethers.provider.send("evm_increaseTime", [86400]);
      await ethers.provider.send("evm_mine");

      // Call debase
      try {
        await tokenPolicy.connect(owner).debase();
        console.log("Debase successful");
      } catch (error) {
        console.error("Debase failed with error:", error.message);
        throw error;
      }

      const totalSupplyAfter = await yieldFuToken.totalSupply();
      console.log("Total Supply after debase:", totalSupplyAfter.toString());
      expect(totalSupplyAfter).to.be.lessThan(totalSupplyBefore);
    });

    it("Should not allow debasement before the interval has passed", async function () {
      await expect(
        tokenPolicy.connect(owner).debase()
      ).to.be.revertedWithCustomError(debaseModule, "DEBASE_TooSoon");
    });
  });
});
