import * as dotenv from "dotenv";
import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "hardhat-storage-layout";
import "@bonadocs/docgen";
import "hardhat-deploy";
import "@nomicfoundation/hardhat-foundry";

dotenv.config();

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.24",
    settings: {
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
    projectDescription: "Biconomy Nexus - Modular Smart Account - ERC-7579",
  },
};

export default config;
