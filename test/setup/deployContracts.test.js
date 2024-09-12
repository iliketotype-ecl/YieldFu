import pkg from "hardhat";
const { ethers } = pkg;

export async function deployContracts({
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
}) {
  const [owner, addr1, addr2] = await ethers.getSigners();

  try {
    // Deploy the Kernel contract
    const Kernel = await ethers.getContractFactory("Kernel");
    const kernel = await Kernel.deploy();
    await kernel.waitForDeployment();
    console.log("TEST: Kernel deployed at:", await kernel.getAddress());

    // Deploy the YieldFuToken
    const YieldFuToken = await ethers.getContractFactory("YieldFuToken");
    const yieldFuToken = await YieldFuToken.deploy(
      "YieldFu",
      "YFU",
      initialSupply,
      owner.address
    );
    await yieldFuToken.waitForDeployment();

    // Deploy the MINTR module
    const MINTR = await ethers.getContractFactory("MINTR");
    const mintrModule = await MINTR.deploy(
      await kernel.getAddress(),
      await yieldFuToken.getAddress(),
      dailyMintCap
    );
    await mintrModule.waitForDeployment();
    console.log(
      "TEST: MINTR module deployed at:",
      await mintrModule.getAddress()
    );

    // Deploy the DEBASE module
    const DEBASE = await ethers.getContractFactory("DEBASE");
    const debaseModule = await DEBASE.deploy(
      await kernel.getAddress(),
      await yieldFuToken.getAddress(),
      debaseRate,
      debaseInterval,
      minDebaseThreshold
    );
    await debaseModule.waitForDeployment();
    console.log(
      "TEST: DEBASE module deployed at:",
      await debaseModule.getAddress()
    );

    // Deploy the STAKE module
    const STAKE = await ethers.getContractFactory("STAKE");
    const stakeModule = await STAKE.deploy(
      await kernel.getAddress(),
      await yieldFuToken.getAddress(),
      baseAPY,
      boostedAPY,
      cooldownPeriod,
      earlyUnstakeSlashRate,
      maxStakeCap
    );
    await stakeModule.waitForDeployment();
    console.log(
      "TEST: STAKE module deployed at:",
      await stakeModule.getAddress()
    );

    // Install the modules in Kernel
    await kernel.executeAction(0, await mintrModule.getAddress(), "0x");
    await kernel.executeAction(0, await debaseModule.getAddress(), "0x");
    await kernel.executeAction(0, await stakeModule.getAddress(), "0x");
    console.log("TEST: Modules installed in Kernel");

    // Deploy and Activate TokenPolicy
    const TokenPolicy = await ethers.getContractFactory("TokenPolicy");
    const tokenPolicy = await TokenPolicy.deploy(
      await kernel.getAddress(),
      await yieldFuToken.getAddress()
    );
    await tokenPolicy.waitForDeployment();
    console.log(
      "TEST: TokenPolicy deployed at:",
      await tokenPolicy.getAddress()
    );

    // Activate TokenPolicy in the Kernel
    await kernel
      .connect(owner)
      .executeAction(2, await tokenPolicy.getAddress(), "0x");
    console.log("TEST: TokenPolicy activated in Kernel");

    // Deploy the StakingPolicy
    const StakingPolicy = await ethers.getContractFactory("StakingPolicy");
    const stakingPolicy = await StakingPolicy.deploy(kernel.getAddress());
    await stakingPolicy.waitForDeployment();
    console.log(
      "TEST: StakingPolicy deployed at:",
      await stakingPolicy.getAddress()
    );

    // Activate StakingPolicy in the Kernel
    await kernel.executeAction(2, await stakingPolicy.getAddress(), "0x");
    console.log("TEST: StakingPolicy activated in Kernel");

    await kernel.setModulePermission(
      await stakeModule.getAddress(),
      await stakingPolicy.getAddress(),
      stakeModule.interface.getFunction("stake").selector,
      true
    );

    await kernel.setModulePermission(
      await stakeModule.getAddress(),
      await stakingPolicy.getAddress(),
      stakeModule.interface.getFunction("unstake").selector,
      true
    );

    await kernel.setModulePermission(
      await stakeModule.getAddress(),
      await stakingPolicy.getAddress(),
      stakeModule.interface.getFunction("getReward").selector,
      true
    );

    await kernel.setModulePermission(
      await stakeModule.getAddress(),
      await stakingPolicy.getAddress(),
      stakeModule.interface.getFunction("boostAPY").selector,
      true
    );

    // Return the deployed contracts for further testing or interaction
    return {
      kernel,
      yieldFuToken,
      mintrModule,
      debaseModule,
      stakeModule,
      tokenPolicy,
      stakingPolicy,
      owner,
      addr1,
      addr2,
    };
  } catch (error) {
    console.error("Error during deployment:", error);
    throw error;
  }
}
