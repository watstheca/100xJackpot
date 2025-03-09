import React, { useState, useEffect, useCallback } from 'react';
import Web3 from 'web3';
import { Contract } from 'web3-eth-contract';
import './styles.css';

// Contract ABIs
import jackpotGameABI from './abi/JackpotGame.json';
import token100xABI from './abi/Token100x.json';
import bondingCurveABI from './abi/BondingCurve.json';

// Constants (replace with your deployed contract addresses)
const JACKPOT_ADDRESS = process.env.REACT_APP_JACKPOT_ADDRESS || '0x5D1c6D024B38666FBf0D2205722288Dd857AB6Fb';
const TOKEN_ADDRESS = process.env.REACT_APP_TOKEN_ADDRESS || '0x0388c8502CA45f04fA5f67a4596fE727c80290C5';
const BONDING_CURVE_ADDRESS = process.env.REACT_APP_BONDING_CURVE_ADDRESS || '0x31Ef1dF550F44FEc3c0285847Ccf8b2a1bc794Cc';
const SONIC_TESTNET_CHAIN_ID = '57054';
const SONIC_TESTNET_RPC_URL = 'https://rpc.blaze.soniclabs.com';

// Button style
const buttonStyle: React.CSSProperties = {
  margin: '5px',
  padding: '10px',
  border: 'none',
  borderRadius: '5px',
  cursor: 'pointer',
  transition: 'background-color 0.2s, transform 0.1s',
};

// Input style
const inputStyle: React.CSSProperties = {
  margin: '5px',
  padding: '10px',
  borderRadius: '5px',
  border: '1px solid #00d4ff',
  background: '#1a1a2e',
  color: 'white',
};

// Card style
const cardStyle: React.CSSProperties = {
  background: 'rgba(22, 33, 62, 0.7)',
  borderRadius: '10px',
  padding: '20px',
  margin: '10px 0',
  boxShadow: '0 4px 6px rgba(0, 0, 0, 0.1)',
};

const App: React.FC = () => {
  // Web3 and contract states
  const [account, setAccount] = useState<string | null>(null);
  const [web3, setWeb3] = useState<Web3 | null>(null);
  const [jackpotContract, setJackpotContract] = useState<Contract | null>(null);
  const [tokenContract, setTokenContract] = useState<Contract | null>(null);
  const [bondingContract, setBondingContract] = useState<Contract | null>(null);
  
  // Game state
  const [totalGuesses, setTotalGuesses] = useState<number>(0);
  const [jackpotAmount, setJackpotAmount] = useState<string>('0');
  const [nextJackpotAmount, setNextJackpotAmount] = useState<string>('0');
  const [playerGuesses, setPlayerGuesses] = useState<number>(0);
  const [guessCost, setGuessCost] = useState<string>('0');
  const [hintCost, setHintCost] = useState<string>('0');
  const [tokenBalance, setTokenBalance] = useState<string>('0');
  const [splits, setSplits] = useState<number[]>([0, 0, 0, 0]);
  const [uniquePlayers, setUniquePlayers] = useState<number>(0);
  const [totalWinners, setTotalWinners] = useState<number>(0);
  
  // User interaction states
  const [guessInput, setGuessInput] = useState<string>('');
  const [nonce, setNonce] = useState<string>('');
  const [buyAmount, setBuyAmount] = useState<string>('');
  const [sellAmount, setSellAmount] = useState<string>('');
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);
  const [hint, setHint] = useState<string | null>(null);
  const [currentHintIndex, setCurrentHintIndex] = useState<number>(0);

  // Pricing information
  const [currentPrice, setCurrentPrice] = useState<string>('0');
  const [estimatedCost, setEstimatedCost] = useState<string>('0');
  const [estimatedUSD, setEstimatedUSD] = useState<string>('$0.00');
  
  // Social feed from DeFAI agent
  const [socialFeed, setSocialFeed] = useState<{type: string, message: string, timestamp: number}[]>([]);
  
  // Loading states
  const [loading, setLoading] = useState<boolean>(false);
  const [loadingHint, setLoadingHint] = useState<boolean>(false);
  const [loadingBuy, setLoadingBuy] = useState<boolean>(false);
  const [loadingSell, setLoadingSell] = useState<boolean>(false);
  const [loadingGuess, setLoadingGuess] = useState<boolean>(false);
  const [loadingReveal, setLoadingReveal] = useState<boolean>(false);
  
  // Show game rules modal
  const [showRules, setShowRules] = useState<boolean>(false);
  
  // Bonding curve visualization data
  const [curveData, setCurveData] = useState<{x: number, y: number}[]>([]);
  const [supplyStats, setSupplyStats] = useState<{
    totalSupply: number,
    sold: number,
    available: number,
    percentageSold: number
  }>({
    totalSupply: 100000000,
    sold: 0,
    available: 100000000,
    percentageSold: 0
  });
  
  // Analytics data
  const [analyticsData, setAnalyticsData] = useState<{
    price24hChange: number,
    volume24h: number,
    marketCap: number
  }>({
    price24hChange: 0,
    volume24h: 0,
    marketCap: 0
  });
  
  // Fetch game stats from contracts
  const fetchGameStats = useCallback(async () => {
    if (!jackpotContract || !tokenContract || !bondingContract || !account || !web3) {
      return;
    }
    
    try {
      setLoading(true);
      
      // Batch all contract calls to improve performance
      const [
        totalGuessesCall,
        jackpotAmountCall,
        nextJackpotAmountCall,
        playerGuessesCall,
        guessCostCall,
        hintCostCall,
        tokenBalanceCall,
        splitCall,
        gameStatsCall,
        currentPriceCall,
        supplyStatsCall
      ] = await Promise.all([
        jackpotContract.methods.totalGuesses().call(),
        jackpotContract.methods.jackpotAmount().call(),
        jackpotContract.methods.nextJackpotAmount().call(),
        jackpotContract.methods.playerGuesses(account).call(),
        jackpotContract.methods.guessCost().call(),
        jackpotContract.methods.hintCost().call(),
        tokenContract.methods.balanceOf(account).call(),
        jackpotContract.methods.getSplit().call(),
        jackpotContract.methods.getGameStats().call(),
        bondingContract.methods.getCurrentPrice().call(),
        bondingContract.methods.getSupplyStats().call()
      ]);

      // Parse results
      const guesses = parseInt(totalGuessesCall);
      const jackpot = web3.utils.fromWei(jackpotAmountCall, 'ether');
      const nextJackpot = web3.utils.fromWei(nextJackpotAmountCall, 'ether');
      const playerGuessCount = parseInt(playerGuessesCall);
      const costGuess = web3.utils.fromWei(guessCostCall, 'mwei');
      const costHint = web3.utils.fromWei(hintCostCall, 'mwei');
      const balance = web3.utils.fromWei(tokenBalanceCall, 'mwei');
      
      // Parse split percentages
      let split: number[] = [0, 0, 0, 0];
      if (Array.isArray(splitCall)) {
        split = splitCall.map((val: string) => parseInt(val));
      } else if (splitCall && typeof splitCall === 'object') {
        const objSplit = splitCall as { [key: string]: string };
        const numericKeys = Object.keys(objSplit)
          .filter(key => !isNaN(Number(key)))
          .slice(0, 4);
        split = numericKeys.map(key => parseInt(objSplit[key] || '0'));
      }
      
      // Parse game stats
      const uniquePlayerCount = parseInt(gameStatsCall[1]);
      const winnersCount = parseInt(gameStatsCall[2]);
      
      // Parse current price and format
      const price = web3.utils.fromWei(currentPriceCall, 'ether');
      
      // Parse supply stats
      const totalSupply = parseInt(supplyStatsCall[0]) / 10**6;
      const sold = parseInt(supplyStatsCall[1]) / 10**6;
      const available = parseInt(supplyStatsCall[2]) / 10**6;
      const percentageSold = parseInt(supplyStatsCall[3]) / 10;
      
      // Update state with all fetched data
      setTotalGuesses(guesses);
      setJackpotAmount(jackpot);
      setNextJackpotAmount(nextJackpot);
      setPlayerGuesses(playerGuessCount);
      setGuessCost(costGuess);
      setHintCost(costHint);
      setTokenBalance(balance);
      setSplits(split);
      setUniquePlayers(uniquePlayerCount);
      setTotalWinners(winnersCount);
      setCurrentPrice(price);
      setSupplyStats({
        totalSupply,
        sold,
        available,
        percentageSold
      });
      
      // Clear any error
      setError(null);
      
      // Generate bonding curve visualization data
      generateBondingCurveData();
      
      // Mock analytics data (in a real app, this would come from an API)
      setAnalyticsData({
        price24hChange: Math.random() * 10 - 5, // Random value between -5% and +5%
        volume24h: Math.floor(Math.random() * 1000) + 500,
        marketCap: sold * parseFloat(price) * 10000
      });
      
    } catch (error) {
      console.error("Fetch game stats error:", error);
      setError(`Failed to fetch game stats: ${error instanceof Error ? error.message : 'Unknown error'}`);
    } finally {
      setLoading(false);
    }
  }, [jackpotContract, tokenContract, bondingContract, account, web3]);
  
  // Generate data for bonding curve visualization
  const generateBondingCurveData = useCallback(() => {
    if (!bondingContract || !web3) return;
    
    const dataPoints = 10;
    const maxTokens = 100000000;
    const data = [];
    
    // Generate 10 points along the curve
    for (let i = 0; i <= dataPoints; i++) {
      const supplyPercentage = i / dataPoints;
      const supply = maxTokens * supplyPercentage;
      
      try {
        // In a production app, we would make actual contract calls
        // Here we'll use a formula that approximates our bonding curve
        // from $0.80 per 10k tokens to $1.20 per 10k tokens
        const initialPrice = 0.00008; // per token
        const finalPrice = 0.00012; // per token
        const price = initialPrice + (finalPrice - initialPrice) * supplyPercentage;
        
        data.push({
          x: supply / 1000000, // Display in millions
          y: price * 10000 // Price per 10k tokens
        });
      } catch (error) {
        console.error("Error generating curve data:", error);
      }
    }
    
    setCurveData(data);
  }, [bondingContract, web3]);
  
  // Initialize Web3 and contracts
  useEffect(() => {
    const initWeb3 = async () => {
      try {
        // Create default Web3 instance with HTTP provider
        let web3Instance = new Web3(new Web3.providers.HttpProvider(SONIC_TESTNET_RPC_URL));
        let accounts: string[] = [];

        // Check if a wallet provider is available
        if (window.ethereum) {
          try {
            // Request access to user's wallet
            accounts = await window.ethereum.request({ method: 'eth_requestAccounts' });
            
            // Create Web3 instance with wallet provider
            web3Instance = new Web3(window.ethereum);
          } catch (connectError) {
            console.warn("Wallet connection error:", connectError);
            setError("Please connect your wallet (MetaMask, Rabby, etc.) to access all features.");
          }
        } else {
          console.warn("No wallet detected. Using read-only mode.");
          setError("No wallet detected. Using read-only mode with limited functionality.");
        }

        // Set the account if available
        if (accounts && accounts.length > 0) {
          setAccount(accounts[0]);
          
          // Check network
          try {
            const chainId = await web3Instance.eth.getChainId();
            if (chainId.toString() !== SONIC_TESTNET_CHAIN_ID) {
              try {
                // Request network switch
                await window.ethereum.request({
                  method: 'wallet_switchEthereumChain',
                  params: [{ chainId: `0x${parseInt(SONIC_TESTNET_CHAIN_ID).toString(16)}` }],
                });
              } catch (switchError: any) {
                // Network not configured, ask to add it
                if (switchError.code === 4902) {
                  await window.ethereum.request({
                    method: 'wallet_addEthereumChain',
                    params: [{
                      chainId: `0x${parseInt(SONIC_TESTNET_CHAIN_ID).toString(16)}`,
                      chainName: 'Sonic Testnet',
                      rpcUrls: [SONIC_TESTNET_RPC_URL],
                      nativeCurrency: { name: 'Sonic', symbol: 'S', decimals: 18 },
                      blockExplorerUrls: ['https://testnet.sonicscan.org'],
                    }],
                  });
                } else {
                  throw switchError;
                }
              }
            }
          } catch (networkError) {
            console.error("Network error:", networkError);
            setError("Please switch to the Sonic Testnet network.");
          }
        }

        // Set Web3 instance
        setWeb3(web3Instance);

        // Initialize contract instances
        const jackpotGame = new web3Instance.eth.Contract(jackpotGameABI as any, JACKPOT_ADDRESS);
        const token100X = new web3Instance.eth.Contract(token100xABI as any, TOKEN_ADDRESS);
        const bondingCurve = new web3Instance.eth.Contract(bondingCurveABI as any, BONDING_CURVE_ADDRESS);

        setJackpotContract(jackpotGame);
        setTokenContract(token100X);
        setBondingContract(bondingCurve);
        
        // Initialize social feed with sample data
        setSocialFeed([
          {
            type: 'GAME_UPDATE',
            message: 'Welcome to 100x Jackpot! Try to guess the secret word and win the jackpot!',
            timestamp: Date.now()
          },
          {
            type: 'NEW_HINT',
            message: 'First hint: The secret is a common word in English.',
            timestamp: Date.now() - 3600000
          }
        ]);

      } catch (error) {
        console.error("Web3 initialization error:", error);
        setError(`Failed to initialize: ${error instanceof Error ? error.message : 'Unknown error'}`);
      }
    };
  
  // Buy 100X tokens
  const buy100X = async () => {
    if (!web3 || !account || !buyAmount || !bondingContract) {
      setError("Wallet not connected, invalid amount, or contract not initialized.");
      return;
    }
    
    try {
      setLoadingBuy(true);
      
      // Clear previous messages
      setError(null);
      setSuccess(null);
      
      // Convert to tokens (considering 6 decimals)
      const tokenAmount = parseInt(buyAmount);
      if (isNaN(tokenAmount) || tokenAmount <= 0) {
        throw new Error("Please enter a valid positive number");
      }
      
      // Calculate cost to buy this amount
      const totalCost = await bondingContract.methods.calculateBuyPrice(tokenAmount).call();
      
      // Check user's S balance
      const userBalance = await web3.eth.getBalance(account);
      if (BigInt(userBalance) < BigInt(totalCost)) {
        throw new Error(`Insufficient S balance: Need ${web3.utils.fromWei(totalCost, 'ether')} S`);
      }
      
      // Execute buy transaction
      const tx = await bondingContract.methods.buy(tokenAmount).send({ 
        from: account,
        value: totalCost,
        gas: 500000 // Adjust gas as needed
      });
      
      // Show success message
      setSuccess(`Successfully bought ${tokenAmount} 100X tokens! Transaction: ${tx.transactionHash}`);
      
      // Update social feed
      if (tokenAmount >= 1000) {
        setSocialFeed(prev => [{
          type: 'BIG_PURCHASE',
          message: `Someone just bought ${tokenAmount} 100X tokens!`,
          timestamp: Date.now()
        }, ...prev.slice(0, 9)]);
      }
      
      // Reset input
      setBuyAmount('');
      
      // Refresh stats
      await fetchGameStats();
    } catch (error) {
      console.error("Buy 100X error:", error);
      setError(`Failed to buy tokens: ${error instanceof Error ? error.message : 'Unknown error'}`);
    } finally {
      setLoadingBuy(false);
    }
  };
  
  // Sell 100X tokens
  const sell100X = async () => {
    if (!web3 || !account || !sellAmount || !bondingContract || !tokenContract) {
      setError("Wallet not connected, invalid amount, or contracts not initialized.");
      return;
    }
    
    try {
      setLoadingSell(true);
      
      // Clear previous messages
      setError(null);
      setSuccess(null);
      
      // Convert to tokens (considering 6 decimals)
      const tokenAmount = parseInt(sellAmount);
      if (isNaN(tokenAmount) || tokenAmount <= 0) {
        throw new Error("Please enter a valid positive number");
      }
      
      // Convert to token units with 6 decimals
      const amount = tokenAmount * 10**6;
      
      // Check user's token balance
      const userBalance = await tokenContract.methods.balanceOf(account).call();
      if (BigInt(userBalance) < BigInt(amount)) {
        throw new Error(`Insufficient 100X balance: Need ${tokenAmount}`);
      }
      
      // Approve tokens for selling
      const currentAllowance = await tokenContract.methods.allowance(account, BONDING_CURVE_ADDRESS).call();
      if (BigInt(currentAllowance) < BigInt(amount)) {
        // Reset allowance if needed
        if (BigInt(currentAllowance) > 0) {
          await tokenContract.methods.approve(BONDING_CURVE_ADDRESS, 0).send({ from: account });
        }
        
        // Approve new amount
        await tokenContract.methods.approve(BONDING_CURVE_ADDRESS, amount).send({ from: account });
      }
      
      // Execute sell transaction
      const tx = await bondingContract.methods.sell(tokenAmount).send({ 
        from: account,
        gas: 500000 // Adjust gas as needed
      });
      
      // Show success message
      setSuccess(`Successfully sold ${tokenAmount} 100X tokens! Transaction: ${tx.transactionHash}`);
      
      // Reset input
      setSellAmount('');
      
      // Refresh stats
      await fetchGameStats();
    } catch (error) {
      console.error("Sell 100X error:", error);
      setError(`Failed to sell tokens: ${error instanceof Error ? error.message : 'Unknown error'}`);
    } finally {
      setLoadingSell(false);
    }
  };
  
  // Commit a guess
  const commitGuess = async () => {
    if (!web3 || !account || !guessInput || !jackpotContract || !tokenContract) {
      setError("Wallet not connected, no guess entered, or contracts not initialized.");
      return;
    }
    
    try {
      setLoadingGuess(true);
      
      // Clear previous messages
      setError(null);
      setSuccess(null);
      
      // Check if game is paused
      const isPaused = await jackpotContract.methods.paused().call();
      if (isPaused) {
        throw new Error("Game is paused. Cannot submit guesses.");
      }
      
      // Check cost and user's token balance
      const cost = await jackpotContract.methods.guessCost().call();
      const userBalance = await tokenContract.methods.balanceOf(account).call();
      
      if (BigInt(userBalance) < BigInt(cost)) {
        throw new Error(`Insufficient 100X balance: Need ${web3.utils.fromWei(cost, 'mwei')} 100X`);
      }
      
      // Approve tokens for guessing
      const currentAllowance = await tokenContract.methods.allowance(account, JACKPOT_ADDRESS).call();
      if (BigInt(currentAllowance) < BigInt(cost)) {
        // Reset allowance if needed
        if (BigInt(currentAllowance) > 0) {
          await tokenContract.methods.approve(JACKPOT_ADDRESS, 0).send({ from: account });
        }
        
        // Approve new amount
        await tokenContract.methods.approve(JACKPOT_ADDRESS, cost).send({ from: account });
      }
      
      // Generate a random nonce
      const nonceValue = web3.utils.randomHex(32);
      
      // Create hash of guess + nonce
      const guessHash = web3.utils.soliditySha3(
        { t: 'string', v: guessInput },
        { t: 'bytes32', v: nonceValue }
      );
      
      if (!guessHash) {
        throw new Error("Failed to generate guess hash");
      }
      
      // Save nonce for later reveal
      setNonce(nonceValue);
      
      // Submit the guess
      const tx = await jackpotContract.methods.commitGuess(guessHash).send({
        from: account,
        gas: 300000 // Adjust gas as needed
      });
      
      // Show success message
      setSuccess("Guess submitted! Wait about 20 seconds before revealing.");
      
      // Update social feed
      setSocialFeed(prev => [{
        type: 'NEW_GUESS',
        message: `Someone just submitted a new guess! Will they win the jackpot?`,
        timestamp: Date.now()
      }, ...prev.slice(0, 9)]);
      
      // Refresh stats
      await fetchGameStats();
    } catch (error) {
      console.error("Commit guess error:", error);
      setError(`Failed to submit guess: ${error instanceof Error ? error.message : 'Unknown error'}`);
    } finally {
      setLoadingGuess(false);
    }
  };
  
  // Reveal a guess
  const revealGuess = async () => {
    if (!web3 || !account || !guessInput || !nonce || !jackpotContract) {
      setError("No guess or nonce available, or contract not initialized.");
      return;
    }
    
    try {
      setLoadingReveal(true);
      
      // Clear previous messages
      setError(null);
      setSuccess(null);
      
      // Reveal the guess
      const tx = await jackpotContract.methods.revealGuess(guessInput, nonce).send({
        from: account,
        gas: 500000 // Adjust gas as needed
      });
      
      // Check if won by looking at events
      const events = tx.events;
      const wonEvent = events && events.GuessRevealed && events.GuessRevealed.returnValues.won === true;
      
      if (wonEvent) {
        // Show winner message
        setSuccess("🎉 CONGRATULATIONS! You won the jackpot! 🎉 Check your wallet for your winnings!");
        
        // Update social feed
        setSocialFeed(prev => [{
          type: 'JACKPOT_WON',
          message: `We have a WINNER! Someone just guessed "${guessInput}" and won the jackpot!`,
          timestamp: Date.now()
        }, ...prev.slice(0, 9)]);
      } else {
        // Show try again message
        setSuccess(`Your guess "${guessInput}" was not correct. Try again!`);
        
        // Show hint suggestion
        const hintCount = await jackpotContract.methods.hintCount().call();
        if (parseInt(hintCount) > 0) {
          setHint(`Wrong guess! There are ${hintCount} hints available. Request a hint to improve your chances!`);
        }
      }
      
      // Reset inputs
      setGuessInput('');
      setNonce('');
      
      // Refresh stats
      await fetchGameStats();
    } catch (error) {
      console.error("Reveal guess error:", error);
      setError(`Failed to reveal guess: ${error instanceof Error ? error.message : 'Unknown error'}`);
    } finally {
      setLoadingReveal(false);
    }
  };
  
  // Request a hint
  const requestHint = async () => {
    if (!web3 || !account || !jackpotContract || !tokenContract) {
      setError("Wallet not connected or contracts not initialized.");
      return;
    }
    
    try {
      setLoadingHint(true);
      
      // Clear previous messages
      setError(null);
      setSuccess(null);
      
      // Check if hints are available
      const hintCount = await jackpotContract.methods.hintCount().call();
      if (parseInt(hintCount) === 0) {
        throw new Error("No hints are available yet.");
      }
      
      // Check cost and user's token balance
      const cost = await jackpotContract.methods.hintCost().call();
      const userBalance = await tokenContract.methods.balanceOf(account).call();
      
      if (BigInt(userBalance) < BigInt(cost)) {
        throw new Error(`Insufficient 100X balance: Need ${web3.utils.fromWei(cost, 'mwei')} 100X`);
      }
      
      // Approve tokens for hint
      const currentAllowance = await tokenContract.methods.allowance(account, JACKPOT_ADDRESS).call();
      if (BigInt(currentAllowance) < BigInt(cost)) {
        // Reset allowance if needed
        if (BigInt(currentAllowance) > 0) {
          await tokenContract.methods.approve(JACKPOT_ADDRESS, 0).send({ from: account });
        }
        
        // Approve new amount
        await tokenContract.methods.approve(JACKPOT_ADDRESS, cost).send({ from: account });
      }
      
      // Request the hint
      const tx = await jackpotContract.methods.requestHint().send({
        from: account,
        gas: 300000 // Adjust gas as needed
      });
      
      // Get the hint
      const hintIndex = parseInt(hintCount) - 1;
      const hintText = await jackpotContract.methods.getHint(hintIndex).call();
      
      // Show hint
      setHint(`Hint #${hintIndex}: ${hintText}`);
      setCurrentHintIndex(hintIndex);
      setSuccess("Hint successfully purchased!");
      
      // Refresh stats
      await fetchGameStats();
    } catch (error) {
      console.error("Request hint error:", error);
      setError(`Failed to request hint: ${error instanceof Error ? error.message : 'Unknown error'}`);
    }

    initWeb3();

    // Setup event listeners for wallet events
    if (window.ethereum) {
      const handleAccountsChanged = (accounts: string[]) => setAccount(accounts[0] || null);
      const handleChainChanged = () => window.location.reload();
      
      window.ethereum.on('accountsChanged', handleAccountsChanged);
      window.ethereum.on('chainChanged', handleChainChanged);
      
      return () => {
        window.ethereum.removeListener('accountsChanged', handleAccountsChanged);
        window.ethereum.removeListener('chainChanged', handleChainChanged);
      };
    }
  }, []);
  
  // Fetch game stats when contracts and account are ready
  useEffect(() => {
    if (jackpotContract && tokenContract && bondingContract && web3) {
      fetchGameStats();
      
      // Set up interval to refresh data
      const interval = setInterval(fetchGameStats, 30000); // Refresh every 30 seconds
      
      return () => clearInterval(interval);
    }
  }, [jackpotContract, tokenContract, bondingContract, account, web3, fetchGameStats]);
  
  // Update estimated cost when buy amount changes
  useEffect(() => {
    const updateEstimatedCost = async () => {
      if (!bondingContract || !web3 || !buyAmount) {
        setEstimatedCost('0');
        setEstimatedUSD('$0.00');
        return;
      }
      
      try {
        // Convert to tokens (considering 6 decimals)
        const tokenAmount = parseInt(buyAmount);
        if (isNaN(tokenAmount) || tokenAmount <= 0) {
          setEstimatedCost('0');
          setEstimatedUSD('$0.00');
          return;
        }
        
        // Calculate cost to buy this amount
        const cost = await bondingContract.methods.calculateBuyPrice(tokenAmount).call();
        const usdCost = await bondingContract.methods.getUsdBuyPrice(tokenAmount).call();
        
        // Format values
        const formattedCost = web3.utils.fromWei(cost, 'ether');
        const formattedUSD = (parseInt(usdCost) / 100).toFixed(2);
        
        setEstimatedCost(formattedCost);
        setEstimatedUSD(`${formattedUSD}`);
      } catch (error) {
        console.error("Error calculating estimated cost:", error);
        setEstimatedCost('Error');
        setEstimatedUSD('Error');
      }
    };
    
    updateEstimatedCost();
  }, [buyAmount, bondingContract, web3]);
  
  // Connect wallet function
  const connectWallet = async () => {
    if (!window.ethereum) {
      setError("Please install MetaMask or another compatible wallet to connect.");
      return;
    }
    
    try {
      // Request account access
      const accounts = await window.ethereum.request({ method: 'eth_requestAccounts' });
      setAccount(accounts[0]);
      
      // Check and switch network
      const web3Instance = new Web3(window.ethereum);
      const chainId = await web3Instance.eth.getChainId();
      
      if (chainId.toString() !== SONIC_TESTNET_CHAIN_ID) {
        try {
          await window.ethereum.request({
            method: 'wallet_switchEthereumChain',
            params: [{ chainId: `0x${parseInt(SONIC_TESTNET_CHAIN_ID).toString(16)}` }],
          });
        } catch (switchError: any) {
          if (switchError.code === 4902) {
            await window.ethereum.request({
              method: 'wallet_addEthereumChain',
              params: [{
                chainId: `0x${parseInt(SONIC_TESTNET_CHAIN_ID).toString(16)}`,
                chainName: 'Sonic Testnet',
                rpcUrls: [SONIC_TESTNET_RPC_URL],
                nativeCurrency: { name: 'Sonic', symbol: 'S', decimals: 18 },
                blockExplorerUrls: ['https://testnet.sonicscan.org'],
              }],
            });
          } else {
            throw switchError;
          }
        }
      }
      
      // Refresh page to get updated state
      window.location.reload();
    } catch (error) {
      console.error("Wallet connection error:", error);
      setError(`Failed to connect wallet: ${error instanceof Error ? error.message : 'Unknown error'}`);
    }
  };