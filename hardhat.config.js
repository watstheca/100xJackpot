require("@nomicfoundation/hardhat-toolbox");
require('dotenv').config();

module.exports = {
  solidity: "0.8.28",
  networks: {
    sonicTestnet: {
      url: process.env.SONIC_RPC_URL || "https://rpc.blaze.soniclabs.com",
      accounts: [process.env.PRIVATE_KEY].filter(Boolean),
      chainId: 57054,
    },
  },
  etherscan: {
    apiKey: {
      sonicTestnet: "no-api-key-needed"
    },
    customChains: [
      {
        network: "sonicTestnet",
        chainId: 57054,
        urls: {
          apiURL: "https://testnet.sonicscan.org/api",
          browserURL: "https://testnet.sonicscan.org"
        }
      }
    ]
  }
};