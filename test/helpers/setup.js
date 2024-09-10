import pkg from "hardhat";
const { ethers } = pkg;

async function deployContracts() {
  const [owner, addr1, addr2] = await ethers.getSigners();

  const DEBASE = await ethers.getContractFactory("DEBASE");
  const STAKE = await ethers.getContractFactory("STAKE");
  const BOND = await ethers.getContractFactory("BOND");
  const ctrl = await ethers.getContractFactory("ctrl");
  const policy = await ethers.getContractFactory("policy");

  const debase = await DEBASE.deploy("DEBASE Token", "DEBASE");
  await debase.waitForDeployment();

  const stake = await STAKE.deploy(
    await debase.getAddress(),
    await debase.getAddress()
  );
  await stake.waitForDeployment();

  const bond = await BOND.deploy(
    await debase.getAddress(),
    await debase.getAddress()
  );
  await bond.waitForDeployment();

  const controller = await ctrl.deploy(
    await debase.getAddress(),
    await stake.getAddress(),
    await bond.getAddress()
  );
  await controller.waitForDeployment();

  const policyContract = await policy.deploy(
    await controller.getAddress(),
    await debase.getAddress(),
    await debase.getAddress()
  );
  await policyContract.waitForDeployment();

  // Grant roles
  await debase.grantRole(
    await debase.CONTROLLER_ROLE(),
    await controller.getAddress()
  );
  await stake.grantRole(
    await stake.CONTROLLER_ROLE(),
    await controller.getAddress()
  );
  await bond.grantRole(
    await bond.CONTROLLER_ROLE(),
    await controller.getAddress()
  );
  await controller.grantRole(await controller.POLICY_ROLE(), owner.address);
  await controller.grantRole(
    await controller.POLICY_ROLE(),
    await policyContract.getAddress()
  );

  // Grant ADMIN_ROLE to the controller on the BOND contract
  await bond.grantRole(
    await bond.DEFAULT_ADMIN_ROLE(),
    await controller.getAddress()
  );

  // Mint initial tokens
  await debase.mint(owner.address, ethers.parseEther("3000000"));
  await debase.mint(await bond.getAddress(), ethers.parseEther("1000000"));
  await debase.mint(
    await controller.getAddress(),
    ethers.parseEther("2000000")
  );
  await debase.mint(
    await policyContract.getAddress(),
    ethers.parseEther("1000000")
  );

  return {
    debase,
    stake,
    bond,
    controller,
    policyContract,
    owner,
    addr1,
    addr2,
  };
}
export { deployContracts };
