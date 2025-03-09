// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

interface IBondingCurve {
    function sell(uint256 gameAmount) external returns (uint256);
    function getPoolInfo() external view returns (uint256 accountingS, uint256 actualS, uint256 tokenBalance);
}

/**
 * @title JackpotGame
 * @dev Optimized jackpot guessing game with DeFAI integration
 */
contract JackpotGame is AccessControl, ReentrancyGuard, Pausable {
    // External contracts
    IERC20 public gameToken;
    IBondingCurve public bondingCurve;
    
    // Game configuration
    address public marketingWallet;
    address public defaiAgent;
    uint256 public guessCost;
    uint256 public hintCost;
    uint256 public revealDelay;
    uint256 public batchInterval;
    
    // Game state
    uint256 public jackpotAmount;
    uint256 public nextJackpotAmount;
    uint256 public totalGuesses;
    bytes32 public secretHash;
    bytes32 public salt;
    uint256 public lastBatchTime;
    uint256 public accumulated100X;
    
    // Statistics
    uint256 public totalWinners;
    uint256 public lastWinTime;
    address public lastWinner;
    uint256 public uniquePlayers;
    
    // Funds distribution
    uint256 public burnPercent = 30;
    uint256 public jackpotPercent = 45;
    uint256 public nextJackpotPercent = 15;
    uint256 public marketingPercent = 10;
    
    // Hint system
    uint256 public hintCount;
    mapping(uint256 => string) public hints;
    
    // User data
    mapping(address => uint256) public playerGuesses;
    mapping(address => bytes32) public commitments;
    mapping(address => uint256) public commitBlocks;
    mapping(address => bool) public hasPlayed;
    
    // Roles
    bytes32 public constant PASSWORD_SETTER_ROLE = keccak256("PASSWORD_SETTER_ROLE");
    bytes32 public constant DEFAI_AGENT_ROLE = keccak256("DEFAI_AGENT_ROLE");
    bytes32 public constant HINT_MANAGER_ROLE = keccak256("HINT_MANAGER_ROLE");
    
    // Events
    event GuessCommitted(address indexed player, bytes32 commitment);
    event GuessRevealed(address indexed player, string guess, bool won);
    event HintRequested(address indexed player, uint256 hintIndex);
    event HintAdded(uint256 index, string hint);
    event GameUpdate(string message);
    event JackpotWon(address indexed winner, uint256 amount, string guess);
    event NewPlayer(address indexed player);
    event SocialAnnouncement(string announcementType, string message);

    constructor(address _gameToken, address _bondingCurve, address _marketingWallet) {
        require(_gameToken != address(0), "Invalid token address");
        require(_bondingCurve != address(0), "Invalid curve address");
        require(_marketingWallet != address(0), "Invalid wallet address");
        
        gameToken = IERC20(_gameToken);
        bondingCurve = IBondingCurve(_bondingCurve);
        marketingWallet = _marketingWallet;
        
        guessCost = 10000 * 10**6; // 10,000 100X
        hintCost = 5000 * 10**6; // 5,000 100X
        revealDelay = 10; // ~20 seconds
        lastBatchTime = block.timestamp;
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PASSWORD_SETTER_ROLE, msg.sender);
        _grantRole(HINT_MANAGER_ROLE, msg.sender);
    }

    function fundJackpot() external payable onlyRole(DEFAULT_ADMIN_ROLE) {
        require(msg.value > 0, "Must send S to fund jackpot");
        jackpotAmount += msg.value;
        emit SocialAnnouncement("JACKPOT_FUNDED", "Jackpot funded!");
    }

    function setSecretHash(bytes32 _hashedSecret, bytes32 _newSalt) external onlyRole(PASSWORD_SETTER_ROLE) whenNotPaused {
        salt = _newSalt;
        secretHash = _hashedSecret;
        emit SocialAnnouncement("NEW_SECRET", "New secret set!");
    }

    function addHint(string memory _hint) external onlyRole(HINT_MANAGER_ROLE) whenNotPaused {
        hints[hintCount] = _hint;
        emit HintAdded(hintCount, _hint);
        hintCount++;
        emit SocialAnnouncement("NEW_HINT", "New hint available!");
    }

    function setDefaiAgent(address _agent) external onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused {
        require(_agent != address(0), "Invalid agent address");
        defaiAgent = _agent;
        _grantRole(DEFAI_AGENT_ROLE, _agent);
    }

    function emitGameUpdate(string memory _message) external whenNotPaused {
        require(msg.sender == defaiAgent || hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Unauthorized");
        emit GameUpdate(_message);
    }

    function commitGuess(bytes32 _commitment) external whenNotPaused nonReentrant {
        require(gameToken.transferFrom(msg.sender, address(this), guessCost), "Transfer failed");
        
        totalGuesses++;
        playerGuesses[msg.sender]++;
        commitments[msg.sender] = _commitment;
        commitBlocks[msg.sender] = block.number;
        
        if (!hasPlayed[msg.sender]) {
            hasPlayed[msg.sender] = true;
            uniquePlayers++;
            emit NewPlayer(msg.sender);
        }
        
        emit GuessCommitted(msg.sender, _commitment);
        accumulated100X += guessCost;

        if (batchInterval > 0 && block.timestamp >= lastBatchTime + (batchInterval * 60)) {
            _processBatch();
        }
    }

    function revealGuess(string memory _guess, bytes32 _nonce) external whenNotPaused nonReentrant {
        require(commitments[msg.sender] != bytes32(0), "No commitment");
        require(block.number >= commitBlocks[msg.sender] + revealDelay, "Reveal too early");
        require(keccak256(abi.encodePacked(_guess, _nonce)) == commitments[msg.sender], "Invalid reveal");

        bool won = (keccak256(abi.encodePacked(_guess, salt)) == secretHash);
        if (won) {
            uint256 payout = (jackpotAmount * 90) / 100;
            uint256 remainder = jackpotAmount - payout;
            uint256 originalNextJackpot = nextJackpotAmount;
            uint256 rollover = (originalNextJackpot * 90) / 100;
            uint256 newNextJackpot = (originalNextJackpot * 10) / 100;
            
            require(address(this).balance >= payout, "Insufficient S for payout");
            jackpotAmount = remainder + rollover;
            nextJackpotAmount = newNextJackpot;
            
            totalWinners++;
            lastWinTime = block.timestamp;
            lastWinner = msg.sender;
            
            (bool sent, ) = msg.sender.call{value: payout}("");
            require(sent, "Payout failed");
            
            emit JackpotWon(msg.sender, payout, _guess);
            emit SocialAnnouncement("JACKPOT_WON", string(abi.encodePacked("Winner! Secret: ", _guess)));
        }

        emit GuessRevealed(msg.sender, _guess, won);
        delete commitments[msg.sender];
        delete commitBlocks[msg.sender];
    }

    function requestHint() external whenNotPaused nonReentrant {
        require(hintCount > 0, "No hints available");
        require(gameToken.transferFrom(msg.sender, address(this), hintCost), "Transfer failed");
        accumulated100X += hintCost;
        
        if (batchInterval > 0 && block.timestamp >= lastBatchTime + (batchInterval * 60)) {
            _processBatch();
        }
        emit HintRequested(msg.sender, hintCount - 1);
    }

    function _processBatch() internal {
        if (accumulated100X == 0) return;

        uint256 total100X = accumulated100X;
        accumulated100X = 0;

        uint256 burnAmount = (total100X * burnPercent) / 100;
        uint256 toSell = total100X - burnAmount;
        uint256 sReceived;

        if (burnAmount > 0) {
            gameToken.transfer(address(0xdead), burnAmount);
        }

        if (toSell > 0) {
            gameToken.approve(address(bondingCurve), toSell);
            sReceived = bondingCurve.sell(toSell);
        }

        uint256 totalNonBurnPercent = jackpotPercent + nextJackpotPercent + marketingPercent;
        uint256 jackpotShare = (sReceived * jackpotPercent) / totalNonBurnPercent;
        uint256 nextJackpotShare = (sReceived * nextJackpotPercent) / totalNonBurnPercent;
        uint256 marketingShare = (sReceived * marketingPercent) / totalNonBurnPercent;

        jackpotAmount += jackpotShare;
        nextJackpotAmount += nextJackpotShare;
        
        if (marketingShare > 0) {
            (bool sent, ) = marketingWallet.call{value: marketingShare}("");
            require(sent, "Marketing transfer failed");
        }

        lastBatchTime = block.timestamp;
    }

    function updateSplit(uint256 _burn, uint256 _jackpot, uint256 _next, uint256 _marketing) external onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused {
        require(_burn + _jackpot + _next + _marketing == 100, "Must sum to 100");
        burnPercent = _burn;
        jackpotPercent = _jackpot;
        nextJackpotPercent = _next;
        marketingPercent = _marketing;
    }

    function setMarketingWallet(address _newWallet) external onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused {
        require(_newWallet != address(0), "Invalid address");
        marketingWallet = _newWallet;
    }

    function setCosts(uint256 _guessCost, uint256 _hintCost) external onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused {
        guessCost = _guessCost;
        hintCost = _hintCost;
    }

    function getHint(uint256 index) external view returns (string memory) {
        require(index < hintCount, "Invalid hint index");
        return hints[index];
    }

    function getSplit() external view returns (uint256, uint256, uint256, uint256) {
        return (burnPercent, jackpotPercent, nextJackpotPercent, marketingPercent);
    }

    function getGameStats() external view returns (uint256, uint256, uint256, uint256) {
        return (totalGuesses, uniquePlayers, totalWinners, jackpotAmount);
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    receive() external payable {
        revert("Use fundJackpot");
    }
}