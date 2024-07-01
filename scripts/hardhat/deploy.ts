import { ethers } from "hardhat";

async function main() {
  const ENTRY_POINT_V7 = "0x0000000071727De22E5E9d8BAf0edAc6f37da032";

  const Nexus = await ethers.getContractFactory("Nexus");

  const smartAccountImpl = await Nexus.deploy(ENTRY_POINT_V7);

  const signers = await ethers.getSigners();

  const factoryOwner = signers[0];

  await smartAccountImpl.waitForDeployment();

  console.log(`Nexus implementation deployed at: ${smartAccountImpl.target}`);

  const Bootstrapper = await ethers.getContractFactory("Bootstrap");

  const bootstrapper = await Bootstrapper.deploy();

  await bootstrapper.waitForDeployment();

  console.log(`Bootstrapper deployed at: ${bootstrapper.target}`);

  const K1Validator = await ethers.getContractFactory("K1Validator");

  const k1Validator = await K1Validator.deploy();

  await k1Validator.waitForDeployment();

  console.log(`K1Validator deployed at: ${k1Validator.target}`);

  const BootstrapLib = await ethers.getContractFactory("BootstrapLib");

  const bootstrapLib = await BootstrapLib.deploy();

  await bootstrapLib.waitForDeployment();

  console.log(`BootstrapLib deployed at: ${bootstrapLib.target}`);

  const K1ValidatorFactory = await ethers.getContractFactory(
    "K1ValidatorFactory",
    {
      libraries: {
        BootstrapLib: await bootstrapLib.getAddress(),
      },
    },
  );

  const k1ValidatorFactory = await K1ValidatorFactory.deploy(
    await smartAccountImpl.getAddress(),
    await factoryOwner.getAddress(),
    await k1Validator.getAddress(),
    await bootstrapper.getAddress(),
  );

  await k1ValidatorFactory.waitForDeployment();

  console.log(`k1ValidatorFactory deployed at: ${k1ValidatorFactory.target}`);

  const BiconomyMetaFactory = await ethers.getContractFactory(
    "BiconomyMetaFactory",
  );

  const biconomyMetaFactory = await BiconomyMetaFactory.deploy(
    await factoryOwner.getAddress(),
  );

  await biconomyMetaFactory.waitForDeployment();

  console.log(`BiconomyMetaFactory deployed at: ${biconomyMetaFactory.target}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => {
    process.exit(0);
  })
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
