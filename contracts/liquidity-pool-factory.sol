// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title SimpleLiquidityPool
 * @dev A simple AMM liquidity pool for token and S pairs
 */
contract SimpleLiquidityPool is ReentrancyGuard {
    IERC20 public token;
    uint256 public tokenReserve;
    uint256 public sReserve;
    uint256 public constant FEE = 30; // 0.3% fee
    uint256 public constant FEE_DENOMINATOR = 10000;
    address public factory;
    
    // LP token tracking
    mapping(address => uint256) public lpBalances;
    uint256 public totalLpSupply;
    
    event Swap(address indexed user, bool isBuy, uint256 tokenAmount, uint256 sAmount);
    event AddLiquidity(address indexed user, uint256 tokenAmount, uint256 sAmount, uint256 lpAmount);
    event RemoveLiquidity(address indexed user, uint256 tokenAmount, uint256 sAmount, uint256 lpAmount);
    
    modifier onlyFactory() {
        require(msg.sender == factory, "Only factory can call");
        _;
    }
    
    constructor(address _token) {
        token = IERC20(_token);
        factory = msg.sender;
    }
    
    /**
     * @dev Initialize pool with initial liquidity
     * @param _tokenAmount Amount of tokens to add
     */
    function initialize(uint256 _tokenAmount) external payable onlyFactory {
        require(tokenReserve == 0 && sReserve == 0, "Already initialized");
        require(_tokenAmount > 0 && msg.value > 0, "Zero amounts");
        
        tokenReserve = _tokenAmount;
        sReserve = msg.value;
        
        // Mint LP tokens to factory
        totalLpSupply = 1000 * 10**18; // Start with 1000 LP tokens
        lpBalances[msg.sender] = totalLpSupply;
    }
    
    /**
     * @dev Get the current price of token in S
     * @return Current price in wei per token
     */
    function getTokenPrice() public view returns (uint256) {
        require(tokenReserve > 0 && sReserve > 0, "Empty reserves");
        return (sReserve * 10**18) / tokenReserve;
    }
    
    /**
     * @dev Swap S for tokens
     * @return tokenAmount Amount of tokens received
     */
    function swapSToToken() external payable nonReentrant returns (uint256 tokenAmount) {
        require(msg.value > 0, "Zero S amount");
        require(tokenReserve > 0 && sReserve > 0, "Empty reserves");
        
        // Calculate token amount with fee
        uint256 sAmountWithFee = msg.value * (FEE_DENOMINATOR - FEE);
        tokenAmount = (tokenReserve * sAmountWithFee) / (sReserve * FEE_DENOMINATOR + sAmountWithFee);
        
        require(tokenAmount > 0, "Zero token amount");
        require(tokenAmount < tokenReserve, "Not enough tokens in reserve");
        
        // Update reserves
        sReserve += msg.value;
        tokenReserve -= tokenAmount;
        
        // Transfer tokens to user
        require(token.transfer(msg.sender, tokenAmount), "Token transfer failed");
        
        emit Swap(msg.sender, true, tokenAmount, msg.value);
        return tokenAmount;
    }
    
    /**
     * @dev Swap tokens for S
     * @param _tokenAmount Amount of tokens to swap
     * @return sAmount Amount of S received
     */
    function swapTokenToS(uint256 _tokenAmount) external nonReentrant returns (uint256 sAmount) {
        require(_tokenAmount > 0, "Zero token amount");
        require(tokenReserve > 0 && sReserve > 0, "Empty reserves");
        
        // Calculate S amount with fee
        uint256 tokenAmountWithFee = _tokenAmount * (FEE_DENOMINATOR - FEE);
        sAmount = (sReserve * tokenAmountWithFee) / (tokenReserve * FEE_DENOMINATOR + tokenAmountWithFee);
        
        require(sAmount > 0, "Zero S amount");
        require(sAmount < sReserve, "Not enough S in reserve");
        
        // Update reserves
        tokenReserve += _tokenAmount;
        sReserve -= sAmount;
        
        // Transfer tokens from user
        require(token.transferFrom(msg.sender, address(this), _tokenAmount), "Token transfer failed");
        
        // Transfer S to user
        payable(msg.sender).transfer(sAmount);
        
        emit Swap(msg.sender, false, _tokenAmount, sAmount);
        return sAmount;
    }
    
    /**
     * @dev Add liquidity to the pool
     * @return lpAmount Amount of LP tokens minted
     */
    function addLiquidity() external payable nonReentrant returns (uint256 lpAmount) {
        require(tokenReserve > 0 && sReserve > 0, "Empty reserves");
        require(msg.value > 0, "Zero S amount");
        
        // Calculate required token amount based on current ratio
        uint256 tokenAmount = (msg.value * tokenReserve) / sReserve;
        require(tokenAmount > 0, "Zero token amount");
        
        // Calculate LP tokens to mint
        lpAmount = (msg.value * totalLpSupply) / sReserve;
        
        // Update reserves
        sReserve += msg.value;
        tokenReserve += tokenAmount;
        totalLpSupply += lpAmount;
        lpBalances[msg.sender] += lpAmount;
        
        // Transfer tokens from user
        require(token.transferFrom(msg.sender, address(this), tokenAmount), "Token transfer failed");
        
        emit AddLiquidity(msg.sender, tokenAmount, msg.value, lpAmount);
        return lpAmount;
    }
    
    /**
     * @dev Remove liquidity from the pool
     * @param _lpAmount Amount of LP tokens to burn
     * @return tokenAmount Amount of tokens received
     * @return sAmount Amount of S received
     */
    function removeLiquidity(uint256 _lpAmount) external nonReentrant returns (uint256 tokenAmount, uint256 sAmount) {
        require(_lpAmount > 0, "Zero LP amount");
        require(lpBalances[msg.sender] >= _lpAmount, "Insufficient LP balance");
        
        // Calculate token and S amounts
        tokenAmount = (_lpAmount * tokenReserve) / totalLpSupply;
        sAmount = (_lpAmount * sReserve) / totalLpSupply;
        
        require(tokenAmount > 0 && sAmount > 0, "Zero amounts");
        
        // Update reserves
        tokenReserve -= tokenAmount;
        sReserve -= sAmount;
        totalLpSupply -= _lpAmount;
        lpBalances[msg.sender] -= _lpAmount;
        
        // Transfer assets to user
        require(token.transfer(msg.sender, tokenAmount), "Token transfer failed");
        payable(msg.sender).transfer(sAmount);
        
        emit RemoveLiquidity(msg.sender, tokenAmount, sAmount, _lpAmount);
        return (tokenAmount, sAmount);
    }
    
    /**
     * @dev Get LP token balance
     * @param _user User address
     * @return LP token balance
     */
    function getLpBalance(address _user) external view returns (uint256) {
        return lpBalances[_user];
    }
    
    /**
     * @dev Get pool reserves
     * @return Pool token and S reserves
     */
    function getReserves() external view returns (uint256, uint256) {
        return (tokenReserve, sReserve);
    }
    
    /**
     * @dev Receive function to accept S
     */
    receive() external payable {
        // Only accept direct S transfers from factory during initialization
        require(msg.sender == factory, "Direct S transfers not allowed");
    }
}

/**
 * @title LiquidityPoolFactory
 * @dev Factory contract to create and manage liquidity pools
 */
contract LiquidityPoolFactory is Ownable, ReentrancyGuard {
    mapping(address => address) public tokenToPool;
    address[] public allPools;
    
    event PoolCreated(address indexed token, address pool, uint256 tokenAmount, uint256 sAmount);
    
    constructor() Ownable(msg.sender) {}
    
    /**
     * @dev Create a new liquidity pool for a token
     * @param _token Token address
     * @param _tokenAmount Amount of tokens to seed
     * @return pool New pool address
     */
    function createPool(address _token, uint256 _tokenAmount) external payable onlyOwner nonReentrant returns (address pool) {
        require(_token != address(0), "Invalid token address");
        require(tokenToPool[_token] == address(0), "Pool already exists");
        require(_tokenAmount > 0 && msg.value > 0, "Zero amounts");
        
        // Ensure the token is valid
        IERC20 token = IERC20(_token);
        require(token.balanceOf(msg.sender) >= _tokenAmount, "Insufficient token balance");
        
        // Create new pool
        SimpleLiquidityPool newPool = new SimpleLiquidityPool(_token);
        
        // Transfer tokens to this contract first
        require(token.transferFrom(msg.sender, address(this), _tokenAmount), "Token transfer failed");
        
        // Approve tokens to pool
        require(token.approve(address(newPool), _tokenAmount), "Token approval failed");
        
        // Initialize pool with liquidity
        newPool.initialize{value: msg.value}(_tokenAmount);
        
        // Store pool info
        tokenToPool[_token] = address(newPool);
        allPools.push(address(newPool));
        
        emit PoolCreated(_token, address(newPool), _tokenAmount, msg.value);
        return address(newPool);
    }
    
    /**
     * @dev Create a new liquidity pool using existing tokens and S
     * @param _token Token address
     * @param _tokenAmount Amount of tokens already in sender's possession
     * @return pool New pool address
     */
    function createPoolWithExistingTokens(
        address _token, 
        uint256 _tokenAmount
    ) external payable onlyOwner nonReentrant returns (address pool) {
        require(_token != address(0), "Invalid token address");
        require(tokenToPool[_token] == address(0), "Pool already exists");
        require(_tokenAmount > 0 && msg.value > 0, "Zero amounts");
        
        // Create new pool
        SimpleLiquidityPool newPool = new SimpleLiquidityPool(_token);
        
        // Transfer tokens directly to pool
        IERC20 token = IERC20(_token);
        require(token.transferFrom(msg.sender, address(newPool), _tokenAmount), "Token transfer failed");
        
        // Initialize pool with liquidity
        newPool.initialize{value: msg.value}(_tokenAmount);
        
        // Store pool info
        tokenToPool[_token] = address(newPool);
        allPools.push(address(newPool));
        
        emit PoolCreated(_token, address(newPool), _tokenAmount, msg.value);
        return address(newPool);
    }
    
    /**
     * @dev Get number of pools created
     * @return Number of pools
     */
    function getPoolCount() external view returns (uint256) {
        return allPools.length;
    }
    
    /**
     * @dev Get pool by token address
     * @param _token Token address
     * @return Pool address
     */
    function getPool(address _token) external view returns (address) {
        return tokenToPool[_token];
    }
    
    /**
     * @dev Allows the owner to rescue accidentally sent tokens
     * @param _token Token address (use address(0) for S)
     * @param _amount Amount to rescue
     */
    function rescueTokens(address _token, uint256 _amount) external onlyOwner {
        if (_token == address(0)) {
            payable(owner()).transfer(_amount);
        } else {
            IERC20(_token).transfer(owner(), _amount);
        }
    }
    
    /**
     * @dev Receive function to accept S
     */
    receive() external payable {}
}
