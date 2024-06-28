import * as dotenv from "dotenv";
import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "hardhat-storage-layout";
import "@bonadocs/docgen";
import "hardhat-deploy";

dotenv.config();

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.26",
    settings: {
      viaIR: true,
      optimizer: {
        enabled: true,
        runs: 1000000,
        details: {
          yul: true,
        },
      },
    },
  },
  docgen: {
    projectName: "Nexus",
    projectDescription: "Nexus - Biconomy Modular Smart Account - ERC-7579",
  },
};

export default config;
