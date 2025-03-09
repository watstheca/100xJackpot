# 100X Jackpot Deployment Guide

This guide will walk you through deploying the entire 100X Jackpot system from scratch, including setting up the DeFAI agent.

## Prerequisites

1. Node.js 16+ and npm/yarn installed
2. Hardhat environment set up
3. MetaMask or Rabby wallet with Sonic testnet S tokens
4. Python 3.8+ for the DeFAI agent
5. GitHub account and Netlify account

## Step 1: Set Up the Backend Environment

First, let's set up the Hardhat project:

1. Create a `.env` file in the project root:

```
# Wallet
PRIVATE_KEY=your_wallet_private_key

# Sonic Testnet
SONIC_RPC_URL=https://rpc.blaze.soniclabs.com

# Contract addresses (will be populated during deployment)
TOKEN_ADDRESS=
BONDING_CURVE_ADDRESS=
JACKPOT_GAME_ADDRESS=
LIQUIDITY_FACTORY_ADDRESS=
DEFAI_AGENT_ADDRESS=

# Twitter API (for the DeFAI agent)
TWITTER_API_KEY=
TWITTER_API_SECRET=
TWITTER_ACCESS_TOKEN=
TWITTER_ACCESS_SECRET=
```

2. Update your `hardhat.config.js`:

```javascript
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
```

3. Install dependencies:

```bash
npm install @openzeppelin/contracts dotenv
```

4. Create directories for contracts, scripts, and artifacts:

```bash
mkdir -p contracts scripts artifacts
```

## Step 2: Deploy Smart Contracts

We'll deploy contracts in sequence and update our `.env` file as we go.

### 1. Deploy Token100x

```bash
npx hardhat run scripts/1-deploy-token.js --network sonicTestnet
```

Take the deployed token address and update your `.env` file:
```
TOKEN_ADDRESS=your_deployed_token_address
```

### 2. Deploy BondingCurve

```bash
npx hardhat run scripts/2-deploy-bonding-curve.js --network sonicTestnet
```

Take the deployed bonding curve address and update your `.env` file:
```
BONDING_CURVE_ADDRESS=your_deployed_bonding_curve_address
```

### 3. Deploy JackpotGame

```bash
npx hardhat run scripts/3-deploy-jackpot-game.js --network sonicTestnet
```

Take the deployed jackpot game address and update your `.env` file:
```
JACKPOT_GAME_ADDRESS=your_deployed_jackpot_game_address
```

### 4. Set Up DeFAI Agent Integration

```bash
npx hardhat run scripts/4-setup-defai-agent.js --network sonicTestnet
```

If you are using a specific wallet for the DeFAI agent, update your `.env` file:
```
DEFAI_AGENT_ADDRESS=your_defai_agent_address
```

### 5. Deploy LiquidityPoolFactory

```bash
npx hardhat run scripts/5-deploy-liquidity-factory.js --network sonicTestnet
```

Take the deployed liquidity pool factory address and update your `.env` file:
```
LIQUIDITY_FACTORY_ADDRESS=your_deployed_factory_address
```

## Step 3: Set Up the DeFAI Agent

1. Create a virtual environment and install dependencies:

```bash
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
pip install web3 python-dotenv zere
```

2. Create directories for the agent:

```bash
mkdir -p agent/abi
```

3. Copy the ABI files to the `agent/abi` directory:

```bash
# You can extract these from the Hardhat artifacts
cp artifacts/contracts/JackpotGame.sol/JackpotGame.json agent/abi/
```

4. Create a `.env` file in the `agent` directory with the same environment variables.

5. Run the DeFAI agent:

```bash
cd agent
python 100x-defai-agent.py
```

## Step 4: Set Up the Frontend

1. Create a React app (if not already created):

```bash
npx create-react-app frontend
cd frontend
```

2. Install dependencies:

```bash
npm install web3 dotenv
```

3. Create a `.env` file in the frontend directory:

```
REACT_APP_JACKPOT_ADDRESS=your_jackpot_contract_address
REACT_APP_TOKEN_ADDRESS=your_token_contract_address
REACT_APP_BONDING_CURVE_ADDRESS=your_bonding_curve_address
```

4. Create directories for the ABI files:

```bash
mkdir -p src/abi
```

5. Copy the ABI files to the frontend:

```bash
cp ../artifacts/contracts/JackpotGame.sol/JackpotGame.json src/abi/
cp ../artifacts/contracts/Token100x.sol/Token100x.json src/abi/
cp ../artifacts/contracts/BondingCurve.sol/BondingCurve.json src/abi/
```

6. Copy the App.tsx file to the src directory.

7. Copy the styles.css file to the src directory.

8. Build the frontend:

```bash
npm run build
```

## Step 5: Deploy to Netlify

1. Log in to your Netlify account.

2. Create a new site from Git.

3. Connect to your GitHub repository.

4. Configure build settings:
   - Build command: `npm run build`
   - Publish directory: `build`

5. Add environment variables:
   - REACT_APP_JACKPOT_ADDRESS
   - REACT_APP_TOKEN_ADDRESS
   - REACT_APP_BONDING_CURVE_ADDRESS

6. Deploy the site.

## Step 6: Testing the Complete System

1. Test buying tokens:
   - Connect your wallet to the frontend
   - Buy some 100X tokens with S

2. Test guessing:
   - Submit a guess
   - Reveal your guess after waiting for the delay

3. Test the DeFAI agent:
   - Verify Twitter posts when events occur
   - Check for on-chain interactions

4. Test the threshold mechanism:
   - Use the admin panel to simulate reaching the 100M threshold
   - Verify liquidity pool creation

## Step 7: Prepare for Hackathon Submission

1. Create a 3-minute demo video:
   - Introduction to 100X Jackpot (30 seconds)
   - Show token economics with bonding curve (30 seconds)
   - Demonstrate gameplay (30 seconds)
   - Showcase DeFAI integration (60 seconds)
   - Show social interaction capabilities (30 seconds)

2. Submit to DoraHacks:
   - Include GitHub repository link
   - Include demo video link
   - Fill out the submission form completely

## Troubleshooting

### Common Issues and Solutions

1. **Transaction Failures**:
   - Ensure you have enough S for gas
   - Check contract allowances
   - Verify you're connected to Sonic testnet

2. **DeFAI Agent Issues**:
   - Check Twitter API credentials
   - Ensure the agent has the correct role in the contract
   - Verify event listeners are working

3. **Frontend Connection Issues**:
   - Clear browser cache
   - Ensure wallet is connected to Sonic testnet
   - Check for console errors

4. **Liquidity Pool Creation Failure**:
   - Verify factory address is set in BondingCurve
   - Check contract balances
   - Review transaction logs for errors

### Contract Verification

To verify contracts on the Sonic block explorer:

```bash
npx hardhat verify --network sonicTestnet CONTRACT_ADDRESS CONSTRUCTOR_ARGS
```

For example:
```bash
npx hardhat verify --network sonicTestnet $TOKEN_ADDRESS
npx hardhat verify --network sonicTestnet $BONDING_CURVE_ADDRESS $TOKEN_ADDRESS
npx hardhat verify --network sonicTestnet $JACKPOT_GAME_ADDRESS $TOKEN_ADDRESS $BONDING_CURVE_ADDRESS $OWNER_ADDRESS
npx hardhat verify --network sonicTestnet $LIQUIDITY_FACTORY_ADDRESS
```
