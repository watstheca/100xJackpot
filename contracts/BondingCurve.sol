// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

// Interface for the Liquidity Pool Factory
interface ILiquidityPoolFactory {
    function createPoolWithExistingTokens(address _token, uint256 _tokenAmount) external payable returns (address pool);
}

/**
 * @title BondingCurve
 * @dev Implements a bonding curve for 100X token with configurable pricing parameters
 */
contract BondingCurve is ReentrancyGuard, Ownable, Pausable {
    IERC20 public token100x;
    uint256 public totalBought; // Gross tokens bought
    uint256 public totalSoldBack; // Gross tokens sold back
    
    // Price configuration (all prices stored as S token amounts in wei)
    uint256 public initialPrice; // Price per token at 0% supply sold
    uint256 public finalPrice; // Price per token at 100% supply sold
    uint256 public currentSUsdPrice; // Current price of S in USD (x100, e.g., $0.50 = 50)
    
    uint256 public constant THRESHOLD = 100_000_000 * 10**6; // 100M 100X
    uint256 public constant MAX_TOKEN_AMOUNT_PER_TX = 10_000_000; // 10M 100X cap per tx
    uint256 public constant PRICE_DECIMALS = 6; // Decimals for price calculations
    uint256 public constant USD_PRICE_DECIMALS = 2; // Decimals for USD price (e.g., 50 = $0.50)
    
    uint256 public poolS; // Accounting of S tokens in the pool (not actual balance)
    uint256 public sellFee = 500; // 5% (500/10000)
    address public jackpotAddress;
    
    // Liquidity Pool Factory address
    address public liquidityPoolFactory;
    address public liquidityPool;
    bool public liquidityPoolCreated;

    // Timelock for full withdrawal
    struct WithdrawRequest {
        uint256 tokenAmount;
        uint256 sAmount;
        uint256 requestTime;
        bool active;
    }
    WithdrawRequest public withdrawRequest;
    uint256 public constant WITHDRAW_DELAY = 24 hours;

    // Events
    event TokenTransferred(uint256 amount);
    event Buy(address indexed buyer, uint256 tokenAmount, uint256 sPaid);
    event Sell(address indexed seller, uint256 tokenAmount, uint256 sReceived);
    event ThresholdReached(uint256 totalBought, uint256 totalSoldBack);
    event SentToLiquidityPool(address indexed pool, uint256 tokenAmount, uint256 sAmount);
    event FullTimelockWithdrawRequested(uint256 tokenAmount, uint256 sAmount, uint256 requestTime);
    event FullTimelockWithdrawExecuted(uint256 tokenAmount, uint256 sAmount);
    event SellFeeUpdated(uint256 newFee);
    event InitialPriceUpdated(uint256 newPrice);
    event FinalPriceUpdated(uint256 newPrice);
    event SUsdPriceUpdated(uint256 newSUsdPrice);
    event LiquidityPoolFactorySet(address factory);
    event LiquidityPoolCreated(address pool, uint256 tokenAmount, uint256 sAmount);

    constructor(address _token100x) Ownable(msg.sender) {
        require(_token100x != address(0), "Invalid token address");
        token100x = IERC20(_token100x);
        
        // Set initial parameters
        // Starting price: $0.80 per 10,000 tokens = 1.6 S per 10,000 tokens
        // = 0.00016 S per token = 160,000,000,000,000 wei per token
        initialPrice = 160_000_000_000_000; // 0.00016 S in wei (per token)
        
        // Final price: $1.20 per 10,000 tokens = 2.4 S per 10,000 tokens
        // = 0.00024 S per token = 240,000,000,000,000 wei per token
        finalPrice = 240_000_000_000_000; // 0.00024 S in wei (per token)
        
        // Set current S token price in USD (x100)
        currentSUsdPrice = 50; // $0.50
        
        jackpotAddress = msg.sender;
        require(token100x.transferFrom(msg.sender, address(this), 110_000_000 * 10**6), "Seed transfer failed");
        _pause();
    }

    /**
     * @dev Set the liquidity pool factory address
     * @param _factory Liquidity pool factory address
     */
    function setLiquidityPoolFactory(address _factory) external onlyOwner {
        require(_factory != address(0), "Invalid factory address");
        liquidityPoolFactory = _factory;
        emit LiquidityPoolFactorySet(_factory);
    }

    /**
     * @dev Set the initial price (price at 0% supply sold)
     * @param _newPrice New price in wei per token
     */
    function setInitialPrice(uint256 _newPrice) external onlyOwner whenPaused {
        require(_newPrice > 0, "Initial price must be greater than 0");
        require(_newPrice < finalPrice, "Initial price must be less than final price");
        initialPrice = _newPrice;
        emit InitialPriceUpdated(_newPrice);
    }

    /**
     * @dev Set the final price (price at 100% supply sold)
     * @param _newPrice New price in wei per token
     */
    function setFinalPrice(uint256 _newPrice) external onlyOwner whenPaused {
        require(_newPrice > initialPrice, "Final price must be greater than initial price");
        finalPrice = _newPrice;
        emit FinalPriceUpdated(_newPrice);
    }

    /**
     * @dev Update the S token price in USD
     * @param _newSUsdPrice New S price in USD (x100, e.g., $0.50 = 50)
     */
    function setSUsdPrice(uint256 _newSUsdPrice) external onlyOwner {
        require(_newSUsdPrice > 0, "S price must be greater than 0");
        currentSUsdPrice = _newSUsdPrice;
        emit SUsdPriceUpdated(_newSUsdPrice);
    }

    /**
     * @dev Set jackpot address
     * @param _jackpotAddress New jackpot address
     */
    function setJackpotAddress(address _jackpotAddress) external onlyOwner {
        require(_jackpotAddress != address(0), "Invalid jackpot address");
        jackpotAddress = _jackpotAddress;
    }

    /**
     * @dev Set sell fee percentage
     * @param _fee New fee (e.g., 500 = 5%)
     */
    function setSellFee(uint256 _fee) external onlyOwner {
        require(_fee <= 1000, "Fee too high"); // Max 10%
        sellFee = _fee;
        emit SellFeeUpdated(_fee);
    }

    /**
     * @dev Calculate current token price based on tokens sold
     * @return Current price in wei per token
     */
    function getCurrentPrice() public view returns (uint256) {
        uint256 netSupply = (totalBought - totalSoldBack) / 10**6;
        uint256 totalSupply = THRESHOLD / 10**6; // 100M tokens in base units
        
        // Linear interpolation between initial and final price based on current supply
        if (netSupply >= totalSupply) {
            return finalPrice;
        } else {
            return initialPrice + (finalPrice - initialPrice) * netSupply / totalSupply;
        }
    }

    /**
     * @dev Calculate cost to buy tokens
     * @param tokenAmount Amount of tokens to buy (in base units, not wei)
     * @return Cost in wei
     */
    function calculateBuyPrice(uint256 tokenAmount) public view returns (uint256) {
        uint256 netSupply = (totalBought - totalSoldBack) / 10**6;
        uint256 totalSupply = THRESHOLD / 10**6; // 100M tokens in base units
        
        // Calculate start price based on current supply
        uint256 startPrice = initialPrice + (finalPrice - initialPrice) * netSupply / totalSupply;
        
        // Calculate end price after adding new tokens
        uint256 endSupply = netSupply + tokenAmount;
        if (endSupply > totalSupply) {
            endSupply = totalSupply;
        }
        uint256 endPrice = initialPrice + (finalPrice - initialPrice) * endSupply / totalSupply;
        
        // Calculate the total cost using the average price (trapezoidal calculation)
        uint256 totalCost = ((startPrice + endPrice) * tokenAmount) / 2;
        
        return totalCost;
    }

    /**
     * @dev Get USD equivalent price for buying tokens (with 2 decimals)
     * @param tokenAmount Amount of tokens to buy (in base units)
     * @return Cost in USD cents (e.g., 100 = $1.00)
     */
    function getUsdBuyPrice(uint256 tokenAmount) external view returns (uint256) {
        uint256 sCost = calculateBuyPrice(tokenAmount);
        // Convert S cost to USD (sCost * 100 / currentSUsdPrice)
        return sCost * 100 / currentSUsdPrice;
    }

    /**
     * @dev Buy tokens
     * @param tokenAmount Amount of tokens to buy (in base units)
     */
    function buy(uint256 tokenAmount) external payable whenNotPaused nonReentrant {
        require(tokenAmount > 0, "Amount must be greater than 0");
        require(tokenAmount <= MAX_TOKEN_AMOUNT_PER_TX, "Amount too large");
        require(totalBought - totalSoldBack + (tokenAmount * 10**6) <= THRESHOLD, "Exceeds threshold");
        
        // Calculate the total cost in wei
        uint256 totalCost = calculateBuyPrice(tokenAmount);
        
        require(msg.value >= totalCost, "Insufficient S sent");
        require(token100x.balanceOf(address(this)) >= tokenAmount * 10**6, "Insufficient 100x in pool");

        token100x.transfer(msg.sender, tokenAmount * 10**6);
        totalBought += tokenAmount * 10**6;
        poolS += totalCost;
        emit Buy(msg.sender, tokenAmount, totalCost);
        
        // Check if threshold reached
        if (totalBought - totalSoldBack >= THRESHOLD) {
            _handleThresholdReached();
        }

        if (msg.value > totalCost) {
            payable(msg.sender).transfer(msg.value - totalCost);
        }
    }

    /**
     * @dev Calculate sell price for tokens
     * @param tokenAmount Amount of tokens to sell (in base units)
     * @return Value in wei
     */
    function calculateSellPrice(uint256 tokenAmount) public view returns (uint256) {
        uint256 netSupply = (totalBought - totalSoldBack) / 10**6;
        uint256 totalSupply = THRESHOLD / 10**6; // 100M tokens
        
        // Calculate end price (current price before selling)
        uint256 endPrice = initialPrice + (finalPrice - initialPrice) * netSupply / totalSupply;
        
        // Calculate start price based on supply after selling
        uint256 startSupply = netSupply > tokenAmount ? netSupply - tokenAmount : 0;
        uint256 startPrice = initialPrice + (finalPrice - initialPrice) * startSupply / totalSupply;
        
        // Calculate the total value using the average price (trapezoidal calculation)
        uint256 totalValue = ((startPrice + endPrice) * tokenAmount) / 2;
        
        return totalValue;
    }

    /**
     * @dev Get USD equivalent for selling tokens (with 2 decimals)
     * @param tokenAmount Amount of tokens to sell (in base units)
     * @return Value in USD cents (e.g., 100 = $1.00) before fees
     */
    function getUsdSellPrice(uint256 tokenAmount) external view returns (uint256) {
        uint256 sValue = calculateSellPrice(tokenAmount);
        // Convert S value to USD (sValue * 100 / currentSUsdPrice)
        return sValue * 100 / currentSUsdPrice;
    }

    /**
     * @dev Sell tokens
     * @param tokenAmount Amount of tokens to sell (in base units)
     */
    function sell(uint256 tokenAmount) external whenNotPaused nonReentrant {
        require(tokenAmount > 0, "Amount must be greater than 0");
        require(tokenAmount <= MAX_TOKEN_AMOUNT_PER_TX, "Amount too large");
        
        // If liquidity pool is active, redirect to pool
        if (liquidityPoolCreated && liquidityPool != address(0)) {
            revert("Bonding curve closed, use liquidity pool");
        }
        
        // Calculate the sell price
        uint256 totalValue = calculateSellPrice(tokenAmount);
        
        // Calculate fees
        uint256 fee = totalValue * sellFee / 10000;
        uint256 jackpotShare = fee / 2; // 2.5%
        uint256 poolShare = fee - jackpotShare; // 2.5%
        uint256 totalReceived = totalValue - fee;
        
        require(poolS >= totalReceived + poolShare, "Insufficient pool S");
        require(address(this).balance >= totalReceived + jackpotShare, "Insufficient S balance");

        // Transfer tokens from seller to the contract
        token100x.transferFrom(msg.sender, address(this), tokenAmount * 10**6);
        totalSoldBack += tokenAmount * 10**6;
        poolS = poolS + poolShare - totalReceived;
        
        // Transfer S to the seller and jackpot
        payable(msg.sender).transfer(totalReceived);
        payable(jackpotAddress).transfer(jackpotShare);
        
        emit Sell(msg.sender, tokenAmount, totalReceived);
        
        // Check if threshold reached
        if (totalBought - totalSoldBack >= THRESHOLD) {
            _handleThresholdReached();
        }
    }

    /**
     * @dev Handle reaching the token threshold
     * Either pauses contract or deploys liquidity pool
     */
    function _handleThresholdReached() internal {
        // Check if we've already created a liquidity pool
        if (liquidityPoolCreated) {
            _pause();
            emit ThresholdReached(totalBought, totalSoldBack);
            return;
        }
        
        // Check if a factory is set
        if (liquidityPoolFactory != address(0)) {
            _createLiquidityPool();
        } else {
            // No factory set, just pause
            _pause();
            emit ThresholdReached(totalBought, totalSoldBack);
        }
    }
    
    /**
     * @dev Create a liquidity pool with AMM using all remaining tokens and S
     */
    function _createLiquidityPool() internal {
        uint256 remainingTokens = token100x.balanceOf(address(this));
        uint256 sBalance = address(this).balance;
        
        // Ensure we have tokens and S
        require(remainingTokens > 0 && sBalance > 0, "No assets to create pool");
        
        // Approve tokens to factory
        token100x.approve(liquidityPoolFactory, remainingTokens);
        
        try ILiquidityPoolFactory(liquidityPoolFactory).createPoolWithExistingTokens{value: sBalance}(
            address(token100x),
            remainingTokens
        ) returns (address newPool) {
            // Mark as created and store pool address
            liquidityPoolCreated = true;
            liquidityPool = newPool;
            
            // Log event
            emit LiquidityPoolCreated(newPool, remainingTokens, sBalance);
            
            // Pause bonding curve
            _pause();
            emit ThresholdReached(totalBought, totalSoldBack);
        } catch {
            // If pool creation fails, just pause
            _pause();
            emit ThresholdReached(totalBought, totalSoldBack);
        }
    }

    /**
     * @dev Manually create the liquidity pool (for admin use)
     * Can be used if automatic creation fails
     */
    function createLiquidityPoolManually() external onlyOwner whenPaused {
        require(!liquidityPoolCreated, "Pool already created");
        require(liquidityPoolFactory != address(0), "Factory not set");
        
        uint256 remainingTokens = token100x.balanceOf(address(this));
        uint256 sBalance = address(this).balance;
        
        // Ensure we have tokens and S
        require(remainingTokens > 0 && sBalance > 0, "No assets to create pool");
        
        // Approve tokens to factory
        token100x.approve(liquidityPoolFactory, remainingTokens);
        
        // Create pool
        address newPool = ILiquidityPoolFactory(liquidityPoolFactory).createPoolWithExistingTokens{value: sBalance}(
            address(token100x),
            remainingTokens
        );
        
        // Mark as created and store pool address
        liquidityPoolCreated = true;
        liquidityPool = newPool;
        
        // Log event
        emit LiquidityPoolCreated(newPool, remainingTokens, sBalance);
    }

    /**
     * @dev Send tokens and S to liquidity pool
     * @param pool Liquidity pool address
     * @param tokenAmount Amount of tokens to send
     * @param sAmount Amount of S to send
     */
    function sendToLiquidityPool(address pool, uint256 tokenAmount, uint256 sAmount) external onlyOwner nonReentrant {
        require(pool != address(0), "Invalid pool address");
        require(tokenAmount > 0 || sAmount > 0, "Nothing to send");
        require(tokenAmount <= token100x.balanceOf(address(this)), "Insufficient 100x balance");
        require(sAmount <= address(this).balance, "Insufficient S balance");

        if (tokenAmount > 0) {
            require(token100x.transfer(pool, tokenAmount), "100x transfer failed");
        }
        if (sAmount > 0) {
            payable(pool).transfer(sAmount);
        }
        emit SentToLiquidityPool(pool, tokenAmount, sAmount);
    }

    /**
     * @dev Request full withdrawal with timelock
     */
    function fullTimelockWithdraw() external onlyOwner nonReentrant {
        require(!withdrawRequest.active, "Withdrawal already requested");
        uint256 tokenAmount = token100x.balanceOf(address(this));
        uint256 sAmount = address(this).balance;
        require(tokenAmount > 0 || sAmount > 0, "Nothing to withdraw");

        withdrawRequest = WithdrawRequest({
            tokenAmount: tokenAmount,
            sAmount: sAmount,
            requestTime: block.timestamp,
            active: true
        });
        emit FullTimelockWithdrawRequested(tokenAmount, sAmount, block.timestamp);
    }

    /**
     * @dev Execute full withdrawal after timelock expires
     */
    function executeFullTimelockWithdraw() external onlyOwner nonReentrant {
        require(withdrawRequest.active, "No active withdrawal request");
        require(block.timestamp >= withdrawRequest.requestTime + WITHDRAW_DELAY, "Timelock not expired");

        uint256 tokenAmount = withdrawRequest.tokenAmount;
        uint256 sAmount = withdrawRequest.sAmount;

        withdrawRequest.active = false;
        withdrawRequest.tokenAmount = 0;
        withdrawRequest.sAmount = 0;
        withdrawRequest.requestTime = 0;

        if (tokenAmount > 0) {
            require(token100x.transfer(owner(), tokenAmount), "100x transfer failed");
        }
        if (sAmount > 0) {
            payable(owner()).transfer(sAmount);
        }
        emit FullTimelockWithdrawExecuted(tokenAmount, sAmount);
    }

    /**
     * @dev Cancel full withdrawal request
     */
    function cancelFullWithdraw() external onlyOwner {
        require(withdrawRequest.active, "No active withdrawal request");
        withdrawRequest.active = false;
        withdrawRequest.tokenAmount = 0;
        withdrawRequest.sAmount = 0;
        withdrawRequest.requestTime = 0;
    }

    /**
     * @dev Pause contract
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Unpause contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }

/**
 * @dev Get pool information
 * @return accountingS The accounting S balance
 * @return actualS The actual S balance in the contract
 * @return tokenBalance The token balance in the contract
 */
function getPoolInfo() external view returns (uint256 accountingS, uint256 actualS, uint256 tokenBalance) {
    return (poolS, address(this).balance, token100x.balanceOf(address(this)));
}

    /**
     * @dev Get current supply statistics
     * @return totalSupply Total supply cap
     * @return sold Total tokens sold
     * @return available Tokens available for sale
     * @return percentageSold Percentage of supply sold (1 decimal, e.g., 256 = 25.6%)
     */
    function getSupplyStats() external view returns (uint256 totalSupply, uint256 sold, uint256 available, uint256 percentageSold) {
        totalSupply = THRESHOLD;
        sold = totalBought - totalSoldBack;
        available = totalSupply > sold ? totalSupply - sold : 0;
        percentageSold = sold * 1000 / totalSupply;
        return (totalSupply, sold, available, percentageSold);
    }

    /**
     * @dev Fallback function - reject direct S transfers
     */
    receive() external payable {
        revert("Contract does not accept direct S transfers");
    }
}