# 100X Jackpot - DeFAI Guessing Game

A decentralized guessing game built on the Sonic Network with DeFAI integration for the Sonic DeFAI Hackathon 2025.

![100X Jackpot Logo](public/logo.png)

## 🎮 Overview

100X Jackpot combines elements of traditional guessing games with DeFi mechanics and AI agents to create an engaging and interactive gaming experience. Players purchase 100X tokens through a bonding curve and use them to guess a secret word. Correct guesses win the jackpot!

### Key Features

- **Bonding Curve Token Economics**: Token price increases as more tokens are purchased
- **Commit-Reveal Guess Mechanism**: Secure two-step guessing process
- **DeFAI Integration**: AI agent monitors events and interacts with both social media and the blockchain
- **Dynamic Jackpot**: Growing prize pool from token transactions
- **Hint System**: Purchase hints to improve your chances

## 🚀 Getting Started

### Prerequisites

- Node.js 16+ and npm/yarn
- MetaMask, Rabby, or another Ethereum-compatible wallet
- Some Sonic testnet S tokens (for testnet usage)

### Installation

1. Clone the repository:

```bash
git clone https://github.com/yourusername/100x-jackpot.git
cd 100x-jackpot
```

2. Install dependencies:

```bash
npm install
```

3. Create a `.env` file with your configuration:

```
REACT_APP_JACKPOT_ADDRESS=your_jackpot_contract_address
REACT_APP_TOKEN_ADDRESS=your_token_contract_address
REACT_APP_BONDING_CURVE_ADDRESS=your_bonding_curve_address
```

4. Start the development server:

```bash
npm start
```

5. Open [http://localhost:3000](http://localhost:3000) to view the app in your browser.

## 🔧 Smart Contracts

The project consists of three main smart contracts:

### Token100x.sol

A standard ERC20 token with 6 decimals and a burning mechanism.

### BondingCurve.sol

Implements a linear bonding curve where:
- Starting price: $0.80 per 10,000 tokens
- Ending price: $1.20 per 10,000 tokens
- Price increases linearly as tokens are purchased
- Supports buying and selling of tokens

### JackpotGame.sol

The main game contract with:
- Commit-reveal pattern for secure guessing
- Jackpot management
- Token batch processing
- DeFAI agent integration
- Hint system

## 🤖 DeFAI Agent

Our DeFAI agent is built using ZerePy and performs both social and on-chain actions:

### Social Actions

- Tweets about new jackpot fundings
- Announces winners
- Shares new hints
- Posts daily summaries
- Creates engagement through milestone posts

### On-Chain Actions

- Monitors events from game contract
- Initiates game updates
- Aggregates statistics
- Helps players with game mechanics
- Manages hint distribution

## 🚀 Deployment

### Testnet Deployment

1. Configure your `hardhat.config.js` with Sonic testnet network settings
2. Deploy the Token100x contract:
   ```bash
   npx hardhat run scripts/1-deploy-token.js --network sonicTestnet
   ```
3. Deploy the BondingCurve contract:
   ```bash
   npx hardhat run scripts/2-deploy-bonding-curve.js --network sonicTestnet
   ```
4. Deploy the JackpotGame contract:
   ```bash
   npx hardhat run scripts/3-deploy-jackpot-game.js --network sonicTestnet
   ```
5. Set up the DeFAI agent:
   ```bash
   npx hardhat run scripts/4-setup-defai-agent.js --network sonicTestnet
   ```

### Mainnet Deployment

For mainnet deployment, follow the same steps but use `--network sonicMainnet`.

## 🛠️ Architecture

```
├── contracts/                # Smart Contracts
│   ├── Token100x.sol         # ERC20 Token contract
│   ├── BondingCurve.sol      # Bonding curve for token economics
│   └── JackpotGame.sol       # Main game logic
├── scripts/                  # Deployment scripts
├── agent/                    # DeFAI agent code
│   └── 100x-defai-agent.py   # ZerePy agent implementation
├── src/                      # Frontend React application
│   ├── App.tsx               # Main application component
│   ├── styles.css            # Styling
│   └── abi/                  # Contract ABIs
└── public/                   # Static assets
```

## 🔄 Game Flow

1. Player buys 100X tokens using S tokens through the bonding curve
2. Player commits a guess (hashed with a nonce) and pays the guess fee in 100X
3. After a short delay, player reveals their guess
4. If correct, player wins the jackpot!
5. If incorrect, player can purchase hints and try again

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the project
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgements

- Sonic Network for the DeFAI Hackathon opportunity
- Zerebro team for the ZerePy framework
- Hey Anon for the inspiration
- DoraHacks for hackathon platform support
