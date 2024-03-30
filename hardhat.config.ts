import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "hardhat-interface-generator";

import dotenv from "dotenv";

dotenv.config();

const deployer_privateKey = process.env.DEPLOYER_PRIVATE_KEY as string;

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.23",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  gasReporter: {
    currency: "USD",
    enabled: true,
    coinmarketcap: process.env.MC_API_KEY as string,
    gasPrice: 19,
    // outputFile: "gas-report.txt",
  },
  networks: {
    arbitrum: {
      url: "https://rpc.ankr.com/arbitrum",
      accounts: [deployer_privateKey],
    },
  },
  etherscan: {
    apiKey: {
      arbitrum: process.env.ARBITRUM_API_KEY as string,
    },
  },
};

export default config;
