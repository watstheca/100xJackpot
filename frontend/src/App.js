import React, { useState, useEffect, useCallback } from 'react';
import Web3 from 'web3';
import JackpotGameABI from './abi/JackpotGame.json';
import Token100xABI from './abi/Token100x.json';
import BondingCurveABI from './abi/BondingCurve.json';

const App = () => {
  // Remove TypeScript type annotations
  const [web3, setWeb3] = useState(null);
  const [accounts, setAccounts] = useState([]);
  const [jackpotContract, setJackpotContract] = useState(null);
  const [tokenContract, setTokenContract] = useState(null);
  const [bondingCurveContract, setBondingCurveContract] = useState(null);
  
  const [currentGuess, setCurrentGuess] = useState('');
  const [lastWinner, setLastWinner] = useState('');
  const [lastWinAmount, setLastWinAmount] = useState('0');
  const [guessChance, setGuessChance] = useState('0');
  const [jackpotValue, setJackpotValue] = useState('0');
  const [hintValue, setHintValue] = useState('');
  const [liquidityValue, setLiquidityValue] = useState('0');
  const [tokenPrice, setTokenPrice] = useState('0');
  const [numTokens, setNumTokens] = useState('1');
  const [totalSupply, setTotalSupply] = useState('0');
  const [buySellMode, setBuySellMode] = useState('buy');
  const [hintCost, setHintCost] = useState('0');
  const [tokenBalance, setTokenBalance] = useState('0');
  const [splits, setSplits] = useState([0, 0, 0, 0]);
  const [uniquePlayers, setUniquePlayers] = useState(0);
  const [totalWinners, setTotalWinners] = useState(0);
  
  const JACKPOT_ADDRESS = process.env.REACT_APP_JACKPOT_ADDRESS || '0x1bCb1B4474b636874E1C35B0CC32ADb408bb43e0';
  const TOKEN_ADDRESS = process.env.REACT_APP_TOKEN_ADDRESS || '0x0755fb9917419a08c90a0Fd245F119202844ec3D';
  const BONDING_CURVE_ADDRESS = process.env.REACT_APP_BONDING_CURVE_ADDRESS || '0x2ECA93adD34C533008b947B2Ed02e4974122D525';

  const loadContractData = useCallback(async (web3, jackpot, token, bondingCurve, account) => {
    try {
      // Load jackpot data
      const jackpotValueWei = await web3.eth.getBalance(JACKPOT_ADDRESS);
      const jackpotValueEth = web3.utils.fromWei(jackpotValueWei, 'ether');
      setJackpotValue(jackpotValueEth);
      
      // Load token data
      const tokenBalanceWei = await token.methods.balanceOf(account).call();
      const tokenBalanceFormatted = web3.utils.fromWei(tokenBalanceWei, 'ether');
      setTokenBalance(tokenBalanceFormatted);
      
      const tokenSupplyWei = await token.methods.totalSupply().call();
      const tokenSupplyFormatted = web3.utils.fromWei(tokenSupplyWei, 'ether');
      setTotalSupply(tokenSupplyFormatted);
      
      // Load bonding curve data
      const liquidityValueWei = await bondingCurve.methods.getPoolBalance().call();
      const liquidityValueEth = web3.utils.fromWei(liquidityValueWei, 'ether');
      setLiquidityValue(liquidityValueEth);
      
      const currentPriceWei = await bondingCurve.methods.getCurrentTokenPrice().call();
      const currentPriceEth = web3.utils.fromWei(currentPriceWei, 'ether');
      setTokenPrice(currentPriceEth);

      // Load game stats
      const lastWinnerAddr = await jackpot.methods.lastWinner().call();
      setLastWinner(lastWinnerAddr);
      
      const lastWinAmountWei = await jackpot.methods.lastWinAmount().call();
      const lastWinAmountEth = web3.utils.fromWei(lastWinAmountWei, 'ether');
      setLastWinAmount(lastWinAmountEth);
      
      const hintCostWei = await jackpot.methods.hintCost().call();
      const hintCostEth = web3.utils.fromWei(hintCostWei, 'ether');
      setHintCost(hintCostEth);
      
      const uniquePlayerCount = await jackpot.methods.getUniquePlayerCount().call();
      setUniquePlayers(uniquePlayerCount);
      
      const winnerCount = await jackpot.methods.getTotalWinners().call();
      setTotalWinners(winnerCount);
      
      // Get split percentages
      const rewardSplit = await jackpot.methods.rewardSplit().call();
      setSplits([
        rewardSplit.winnerSplitPct,
        rewardSplit.bonusSplitPct,
        rewardSplit.tokenHolderSplitPct,
        rewardSplit.liquiditySplitPct
      ]);
    } catch (error) {
      console.error("Error loading contract data:", error);
    }
  }, [JACKPOT_ADDRESS, TOKEN_ADDRESS, BONDING_CURVE_ADDRESS]);

  useEffect(() => {
    const initWeb3 = async () => {
      if (window.ethereum) {
        try {
          // Request account access
          await window.ethereum.request({ method: 'eth_requestAccounts' });
          const web3Instance = new Web3(window.ethereum);
          setWeb3(web3Instance);
          
          // Get user accounts
          const accts = await web3Instance.eth.getAccounts();
          setAccounts(accts);
          
          // Initialize contracts
          const jackpotInstance = new web3Instance.eth.Contract(JackpotGameABI.abi, JACKPOT_ADDRESS);
          const tokenInstance = new web3Instance.eth.Contract(Token100xABI.abi, TOKEN_ADDRESS);
          const bondingCurveInstance = new web3Instance.eth.Contract(BondingCurveABI.abi, BONDING_CURVE_ADDRESS);
          
          setJackpotContract(jackpotInstance);
          setTokenContract(tokenInstance);
          setBondingCurveContract(bondingCurveInstance);
          
          // Load initial data
          await loadContractData(web3Instance, jackpotInstance, tokenInstance, bondingCurveInstance, accts[0]);
        } catch (error) {
          console.error("User denied account access or error occurred:", error);
        }
      } else {
        console.log('Please install MetaMask!');
      }
    };
    
    initWeb3();
  }, [JACKPOT_ADDRESS, TOKEN_ADDRESS, BONDING_CURVE_ADDRESS, loadContractData]);

  const makeGuess = async () => {
    if (!jackpotContract || !web3 || !accounts[0] || !currentGuess) return;
    
    try {
      await jackpotContract.methods.makeGuess(currentGuess).send({
        from: accounts[0],
        value: web3.utils.toWei('0.002', 'ether')
      });
      
      // Reload contract data after guess
      await loadContractData(web3, jackpotContract, tokenContract, bondingCurveContract, accounts[0]);
      setCurrentGuess('');
    } catch (error) {
      console.error("Error making guess:", error);
    }
  };

  const buyTokens = async () => {
    if (!bondingCurveContract || !web3 || !accounts[0] || !numTokens) return;
    
    const numTokensWei = web3.utils.toWei(numTokens, 'ether');
    
    try {
      // Calculate cost in ETH
      const costWei = await bondingCurveContract.methods.getTokenBuyPrice(numTokensWei).call();
      
      await bondingCurveContract.methods.buyTokens(numTokensWei).send({
        from: accounts[0],
        value: costWei
      });
      
      // Reload contract data
      await loadContractData(web3, jackpotContract, tokenContract, bondingCurveContract, accounts[0]);
    } catch (error) {
      console.error("Error buying tokens:", error);
    }
  };

  const sellTokens = async () => {
    if (!bondingCurveContract || !web3 || !accounts[0] || !numTokens) return;
    
    const numTokensWei = web3.utils.toWei(numTokens, 'ether');
    
    try {
      // Check if token is approved
      const allowance = await tokenContract.methods.allowance(accounts[0], BONDING_CURVE_ADDRESS).call();
      
      if (parseInt(allowance) < parseInt(numTokensWei)) {
        // Approve tokens
        await tokenContract.methods.approve(BONDING_CURVE_ADDRESS, numTokensWei).send({
          from: accounts[0]
        });
      }
      
      await bondingCurveContract.methods.sellTokens(numTokensWei).send({
        from: accounts[0]
      });
      
      // Reload contract data
      await loadContractData(web3, jackpotContract, tokenContract, bondingCurveContract, accounts[0]);
    } catch (error) {
      console.error("Error selling tokens:", error);
    }
  };

  const getHint = async () => {
    if (!jackpotContract || !web3 || !accounts[0]) return;
    
    try {
      // Check if token is approved
      const allowance = await tokenContract.methods.allowance(accounts[0], JACKPOT_ADDRESS).call();
      const hintCostWei = await jackpotContract.methods.hintCost().call();
      
      if (parseInt(allowance) < parseInt(hintCostWei)) {
        // Approve tokens
        await tokenContract.methods.approve(JACKPOT_ADDRESS, hintCostWei).send({
          from: accounts[0]
        });
      }
      
      const hint = await jackpotContract.methods.getHint().call({
        from: accounts[0]
      });
      
      setHintValue(hint);
      
      // Reload token balance
      const tokenBalanceWei = await tokenContract.methods.balanceOf(accounts[0]).call();
      const tokenBalanceFormatted = web3.utils.fromWei(tokenBalanceWei, 'ether');
      setTokenBalance(tokenBalanceFormatted);
    } catch (error) {
      console.error("Error getting hint:", error);
    }
  };

  const calculateGuessChance = useCallback(async () => {
    if (!jackpotContract || !web3 || !accounts[0] || !currentGuess) return;
    
    try {
      const chance = await jackpotContract.methods.calculateGuessChance(currentGuess).call();
      setGuessChance(chance / 100 + '%');
    } catch (error) {
      console.error("Error calculating guess chance:", error);
      setGuessChance('0%');
    }
  }, [jackpotContract, web3, accounts, currentGuess]);

  useEffect(() => {
    if (currentGuess && jackpotContract && web3 && accounts[0]) {
      calculateGuessChance();
    }
  }, [currentGuess, jackpotContract, web3, accounts, calculateGuessChance]);

  return (
    <div className="app-container">
      <header>
        <h1>100X Jackpot Game</h1>
        <p>Connected: {accounts.length > 0 ? accounts[0] : 'Not connected'}</p>
      </header>
      
      <main>
        <section className="game-section">
          <h2>Jackpot Game</h2>
          <div className="jackpot-info">
            <p>Current Jackpot: {jackpotValue} ETH</p>
            <p>Last Winner: {lastWinner.substring(0, 6)}...{lastWinner.substring(lastWinner.length - 4)}</p>
            <p>Last Win Amount: {lastWinAmount} ETH</p>
            <p>Unique Players: {uniquePlayers}</p>
            <p>Total Winners: {totalWinners}</p>
          </div>
          
          <div className="game-controls">
            <input 
              type="text" 
              placeholder="Enter your guess" 
              value={currentGuess} 
              onChange={(e) => setCurrentGuess(e.target.value)}
            />
            <p>Guess Chance: {guessChance}</p>
            <button onClick={makeGuess}>Make Guess (0.002 ETH)</button>
          </div>
          
          <div className="hint-section">
            <button onClick={getHint}>Get Hint ({hintCost} 100X Tokens)</button>
            {hintValue && <p>Hint: {hintValue}</p>}
          </div>
        </section>
        
        <section className="token-section">
          <h2>100X Token</h2>
          <div className="token-info">
            <p>Your Balance: {tokenBalance} 100X</p>
            <p>Total Supply: {totalSupply} 100X</p>
            <p>Current Price: {tokenPrice} ETH</p>
            <p>Liquidity Pool: {liquidityValue} ETH</p>
          </div>
          
          <div className="token-controls">
            <div className="mode-toggle">
              <button 
                className={buySellMode === 'buy' ? 'active' : ''} 
                onClick={() => setBuySellMode('buy')}
              >
                Buy
              </button>
              <button 
                className={buySellMode === 'sell' ? 'active' : ''} 
                onClick={() => setBuySellMode('sell')}
              >
                Sell
              </button>
            </div>
            
            <input 
              type="number" 
              min="0" 
              step="1" 
              placeholder="Amount of tokens" 
              value={numTokens} 
              onChange={(e) => setNumTokens(e.target.value)}
            />
            
            {buySellMode === 'buy' ? (
              <button onClick={buyTokens}>Buy Tokens</button>
            ) : (
              <button onClick={sellTokens}>Sell Tokens</button>
            )}
          </div>
        </section>
        
        <section className="reward-split">
          <h2>Reward Distribution</h2>
          <div className="split-bars">
            <div className="split-bar">
              <div className="bar-fill" style={{width: `${splits[0]}%`}}></div>
              <p>Winner: {splits[0]}%</p>
            </div>
            <div className="split-bar">
              <div className="bar-fill" style={{width: `${splits[1]}%`}}></div>
              <p>Bonus: {splits[1]}%</p>
            </div>
            <div className="split-bar">
              <div className="bar-fill" style={{width: `${splits[2]}%`}}></div>
              <p>Token Holders: {splits[2]}%</p>
            </div>
            <div className="split-bar">
              <div className="bar-fill" style={{width: `${splits[3]}%`}}></div>
              <p>Liquidity: {splits[3]}%</p>
            </div>
          </div>
        </section>
      </main>
      
      <footer>
        <p>DeFAI Hackathon Project - Sonic Chain - 2024</p>
      </footer>
    </div>
  );
};

export default App;