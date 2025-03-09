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
 * @dev Jackpot guessing game with DeFAI agent integration
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
    
    // Statistics for DeFAI agents
    uint256 public totalWinners;
    uint256 public totalPayouts;
    uint256 public lastWinTime;
    address public lastWinner;
    uint256 public uniquePlayers;
    
    // Funds distribution
    uint256 public burnPercent;
    uint256 public jackpotPercent;
    uint256 public nextJackpotPercent;
    uint256 public marketingPercent;
    
    // Hint system
    uint256 public hintCount;
    mapping(uint256 => string) public hints;
    
    // User data storage
    mapping(address => uint256) public playerGuesses;
    mapping(address => bytes32) public commitments;
    mapping(address => uint256) public commitBlocks;
    mapping(address => bool) public hasPlayed;
    
    // Contract upgrade
    struct ChangeRequest {
        address newGameToken;
        address newBondingCurve;
        uint256 requestTime;
        bool active;
    }
    ChangeRequest public changeRequest;
    uint256 public constant CHANGE_DELAY = 24 hours;
    
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
    event SplitUpdated(uint256 burn, uint256 jackpot, uint256 next, uint256 marketing);
    event MarketingWalletUpdated(address newWallet);
    event DefaiAgentUpdated(address newAgent);
    event CostsUpdated(uint256 newGuessCost, uint256 newHintCost);
    event SecretHashSet(bytes32 hashedSecret);
    event BatchProcessed(uint256 total100X, uint256 sReceived);
    event RevealDelayUpdated(uint256 newDelay);
    event GameTokenChangeRequested(address newToken, uint256 requestTime);
    event BondingCurveChangeRequested(address newCurve, uint256 requestTime);
    event ChangeExecuted(address newGameToken, address newBondingCurve);
    event ChangeCancelled();
    event JackpotFunded(uint256 amount);
    
    // DeFAI-specific events
    event JackpotWon(address indexed winner, uint256 amount, string guess);
    event NewPlayer(address indexed player);
    event SocialAnnouncement(string announcementType, string message);

    constructor(address _gameToken, address _bondingCurve, address _marketingWallet) {
        require(_gameToken != address(0), "Invalid game token address");
        require(_bondingCurve != address(0), "Invalid bonding curve address");
        require(_marketingWallet != address(0), "Invalid marketing wallet address");
        
        // Initialize contract addresses
        gameToken = IERC20(_gameToken);
        bondingCurve = IBondingCurve(_bondingCurve);
        marketingWallet = _marketingWallet;
        
        // Set default game parameters
        guessCost = 10000 * 10**6; // 10,000 100X
        hintCost = 5000 * 10**6; // 5,000 100X
        revealDelay = 10; // ~20 seconds
        
        // Set fund distribution percentages
        burnPercent = 30;
        jackpotPercent = 45;
        nextJackpotPercent = 15;
        marketingPercent = 10;
        
        // Verify percentages add up to 100%
        require(burnPercent + jackpotPercent + nextJackpotPercent + marketingPercent == 100, "Split must sum to 100");
        
        // Initialize timestamps
        lastBatchTime = block.timestamp;
        
        // Set up roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PASSWORD_SETTER_ROLE, msg.sender);
        _grantRole(HINT_MANAGER_ROLE, msg.sender);
    }

    /**
     * @dev Fund the jackpot with S tokens
     */
    function fundJackpot() external payable onlyRole(DEFAULT_ADMIN_ROLE) {
        require(msg.value > 0, "Must send S to fund jackpot");
        jackpotAmount += msg.value;
        emit JackpotFunded(msg.value);
        
        // Emit social announcement for DeFAI agent
        string memory message = string(abi.encodePacked(
            "Jackpot funded with ", 
            _uintToString(msg.value / 10**18), 
            ".",
            _uintToString((msg.value % 10**18) / 10**16),
            " S! Current jackpot is now ",
            _uintToString(jackpotAmount / 10**18),
            ".",
            _uintToString((jackpotAmount % 10**18) / 10**16),
            " S!"
        ));
        emit SocialAnnouncement("JACKPOT_FUNDED", message);
    }

    /**
     * @dev Set the secret hash and salt for the guessing game
     * @param _hashedSecret Hashed secret
     * @param _newSalt New salt value
     */
    function setSecretHash(bytes32 _hashedSecret, bytes32 _newSalt) external onlyRole(PASSWORD_SETTER_ROLE) whenNotPaused {
        salt = _newSalt;
        secretHash = _hashedSecret;
        emit SecretHashSet(_hashedSecret);
        
        // Emit social announcement for DeFAI agent
        emit SocialAnnouncement("NEW_SECRET", "A new secret has been set! Can you guess it?");
    }

    /**
     * @dev Add a hint for the current secret
     * @param _hint Hint text
     */
    function addHint(string memory _hint) external onlyRole(HINT_MANAGER_ROLE) whenNotPaused {
        hints[hintCount] = _hint;
        emit HintAdded(hintCount, _hint);
        hintCount++;
        
        // Emit social announcement for DeFAI agent
        string memory message = string(abi.encodePacked(
            "New hint added! Hint #",
            _uintToString(hintCount - 1),
            " is now available."
        ));
        emit SocialAnnouncement("NEW_HINT", message);
    }

    /**
     * @dev Set the DeFAI agent address
     * @param _agent New agent address
     */
    function setDefaiAgent(address _agent) external onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused {
        require(_agent != address(0), "Invalid agent address");
        defaiAgent = _agent;
        _grantRole(DEFAI_AGENT_ROLE, _agent);
        emit DefaiAgentUpdated(_agent);
    }

    /**
     * @dev Set the reveal delay
     * @param _newDelay New delay in blocks
     */
    function setRevealDelay(uint256 _newDelay) external onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused {
        require(_newDelay >= 5, "Delay too short");
        revealDelay = _newDelay;
        emit RevealDelayUpdated(_newDelay);
    }

    /**
     * @dev Set the batch interval
     * @param _minutes New interval in minutes
     */
    function setBatchInterval(uint256 _minutes) external onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused {
        batchInterval = _minutes;
        lastBatchTime = block.timestamp;
    }

    /**
     * @dev Request game token change with timelock
     * @param _newToken New token address
     */
    function requestGameTokenChange(address _newToken) external onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused {
        require(_newToken != address(0), "Invalid token address");
        require(!changeRequest.active, "Change already requested");
        changeRequest = ChangeRequest({
            newGameToken: _newToken,
            newBondingCurve: address(bondingCurve),
            requestTime: block.timestamp,
            active: true
        });
        emit GameTokenChangeRequested(_newToken, block.timestamp);
    }

    /**
     * @dev Request bonding curve change with timelock
     * @param _newCurve New bonding curve address
     */
    function requestBondingCurveChange(address _newCurve) external onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused {
        require(_newCurve != address(0), "Invalid bonding curve address");
        require(!changeRequest.active, "Change already requested");
        changeRequest = ChangeRequest({
            newGameToken: address(gameToken),
            newBondingCurve: _newCurve,
            requestTime: block.timestamp,
            active: true
        });
        emit BondingCurveChangeRequested(_newCurve, block.timestamp);
    }

    /**
     * @dev Execute change request after timelock expires
     */
    function executeChange() external onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused {
        require(changeRequest.active, "No active change request");
        require(block.timestamp >= changeRequest.requestTime + CHANGE_DELAY, "Timelock not expired");

        if (changeRequest.newGameToken != address(gameToken)) {
            gameToken = IERC20(changeRequest.newGameToken);
        }
        if (changeRequest.newBondingCurve != address(bondingCurve)) {
            bondingCurve = IBondingCurve(changeRequest.newBondingCurve);
        }

        emit ChangeExecuted(changeRequest.newGameToken, changeRequest.newBondingCurve);
        delete changeRequest;
    }

    /**
     * @dev Cancel active change request
     */
    function cancelChange() external onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused {
        require(changeRequest.active, "No active change request");
        delete changeRequest;
        emit ChangeCancelled();
    }

    /**
     * @dev Allow DeFAI agent to emit game updates
     * @param _message Update message
     */
    function emitGameUpdate(string memory _message) external whenNotPaused {
        require(msg.sender == defaiAgent || hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Unauthorized");
        emit GameUpdate(_message);
    }

    /**
     * @dev Commit a guess to the game (step 1 of commit-reveal pattern)
     * @param _commitment Hashed guess with nonce
     */
    function commitGuess(bytes32 _commitment) external whenNotPaused nonReentrant {
        require(gameToken.transferFrom(msg.sender, address(this), guessCost), "Transfer failed");
        
        // Update game metrics
        totalGuesses++;
        playerGuesses[msg.sender]++;
        commitments[msg.sender] = _commitment;
        commitBlocks[msg.sender] = block.number;
        
        // Track unique players
        if (!hasPlayed[msg.sender]) {
            hasPlayed[msg.sender] = true;
            uniquePlayers++;
            emit NewPlayer(msg.sender);
        }
        
        emit GuessCommitted(msg.sender, _commitment);

        // Add tokens to accumulated batch
        accumulated100X += guessCost;

        // Process batch if interval has passed
        if (batchInterval > 0 && block.timestamp >= lastBatchTime + (batchInterval * 60)) {
            _processBatch();
        }
    }

    /**
     * @dev Reveal a previously committed guess (step 2 of commit-reveal pattern)
     * @param _guess The actual guess in plain text
     * @param _nonce Random value used when committing
     */
    function revealGuess(string memory _guess, bytes32 _nonce) external whenNotPaused nonReentrant {
        require(commitments[msg.sender] != bytes32(0), "No commitment");
        require(block.number >= commitBlocks[msg.sender] + revealDelay, "Reveal too early");
        require(keccak256(abi.encodePacked(_guess, _nonce)) == commitments[msg.sender], "Invalid reveal");

        bool won = (keccak256(abi.encodePacked(_guess, salt)) == secretHash);
        if (won) {
            // Calculate payouts
            uint256 payout = (jackpotAmount * 90) / 100;
            uint256 remainder = jackpotAmount - payout;
            uint256 originalNextJackpot = nextJackpotAmount;
            uint256 rollover = (originalNextJackpot * 90) / 100;
            uint256 newNextJackpot = (originalNextJackpot * 10) / 100;
            
            // Update game state
            require(address(this).balance >= payout, "Insufficient S for payout");
            jackpotAmount = remainder + rollover;
            nextJackpotAmount = newNextJackpot;
            
            // Update statistics
            totalWinners++;
            totalPayouts += payout;
            lastWinTime = block.timestamp;
            lastWinner = msg.sender;
            
            // Transfer winnings
            (bool sent, ) = msg.sender.call{value: payout}("");
            require(sent, "Payout failed");
            
            // Emit events for DeFAI
            emit JackpotWon(msg.sender, payout, _guess);
            
            string memory message = string(abi.encodePacked(
                "We have a winner! ",
                _truncateAddress(msg.sender),
                " just won ",
                _uintToString(payout / 10**18),
                ".",
                _uintToString((payout % 10**18) / 10**16),
                " S by guessing the secret: ",
                _guess
            ));
            emit SocialAnnouncement("JACKPOT_WON", message);
        }

        emit GuessRevealed(msg.sender, _guess, won);
        delete commitments[msg.sender];
        delete commitBlocks[msg.sender];

        // Process tokens for guess reveal if needed
        if (!won && batchInterval > 0 && block.timestamp >= lastBatchTime + (batchInterval * 60)) {
            _processBatch();
        }
    }

    /**
     * @dev Request a hint by spending tokens
     */
    function requestHint() external whenNotPaused nonReentrant {
        require(hintCount > 0, "No hints available");
        require(gameToken.transferFrom(msg.sender, address(this), hintCost), "Transfer failed");

        accumulated100X += hintCost;

        // Process batch if interval has passed
        if (batchInterval > 0 && block.timestamp >= lastBatchTime + (batchInterval * 60)) {
            _processBatch();
        }

        emit HintRequested(msg.sender, hintCount - 1);
    }

    /**
     * @dev Process accumulated tokens and distribute S
     */
    function _processBatch() internal {
        if (accumulated100X == 0) return;

        uint256 total100X = accumulated100X;
        accumulated100X = 0;

        // Calculate burn amount
        uint256 burnAmount = (total100X * burnPercent) / 100;
        uint256 toSell = total100X - burnAmount;
        uint256 sReceived;

        // Burn tokens
        if (burnAmount > 0) {
            require(gameToken.transfer(address(0xdead), burnAmount), "Burn failed");
        }

        // Sell tokens through bonding curve
        if (toSell > 0) {
            require(gameToken.approve(address(bondingCurve), toSell), "Approval failed");
            sReceived = bondingCurve.sell(toSell);
        }

        // Distribute S tokens
        uint256 totalNonBurnPercent = jackpotPercent + nextJackpotPercent + marketingPercent;
        require(totalNonBurnPercent > 0, "Non-burn percentages must be greater than 0");
        
        uint256 jackpotShare = (sReceived * jackpotPercent) / totalNonBurnPercent;
        uint256 nextJackpotShare = (sReceived * nextJackpotPercent) / totalNonBurnPercent;
        uint256 marketingShare = (sReceived * marketingPercent) / totalNonBurnPercent;

        // Adjust for rounding errors
        uint256 totalDistributed = jackpotShare + nextJackpotShare + marketingShare;
        if (sReceived > totalDistributed) {
            jackpotShare += sReceived - totalDistributed;
        }

        // Update jackpot amounts
        jackpotAmount += jackpotShare;
        nextJackpotAmount += nextJackpotShare;
        
        // Verify sufficient balance
        require(address(this).balance >= jackpotAmount + nextJackpotAmount, "Insufficient S balance");
        
        // Transfer marketing share
        if (marketingShare > 0) {
            (bool sent, ) = marketingWallet.call{value: marketingShare}("");
            require(sent, "Marketing transfer failed");
        }

        lastBatchTime = block.timestamp;
        emit BatchProcessed(total100X, sReceived);
        
        // Emit social announcement if significant batch
        if (total100X >= 1_000_000 * 10**6) { // If batch > 1M tokens
            string memory message = string(abi.encodePacked(
                "Large batch processed! ",
                _uintToString(total100X / 10**6),
                " 100X tokens processed, increasing the jackpot by ",
                _uintToString(jackpotShare / 10**18),
                ".",
                _uintToString((jackpotShare % 10**18) / 10**16),
                " S."
            ));
            emit SocialAnnouncement("LARGE_BATCH", message);
        }
    }

    /**
     * @dev Update the split percentages for token distribution
     * @param _burn Burn percentage
     * @param _jackpot Jackpot percentage
     * @param _next Next jackpot percentage
     * @param _marketing Marketing percentage
     */
    function updateSplit(uint256 _burn, uint256 _jackpot, uint256 _next, uint256 _marketing) external onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused {
        require(_burn + _jackpot + _next + _marketing == 100, "Must sum to 100");
        burnPercent = _burn;
        jackpotPercent = _jackpot;
        nextJackpotPercent = _next;
        marketingPercent = _marketing;
        emit SplitUpdated(_burn, _jackpot, _next, _marketing);
    }

    /**
     * @dev Set marketing wallet address
     * @param _newWallet New wallet address
     */
    function setMarketingWallet(address _newWallet) external onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused {
        require(_newWallet != address(0), "Invalid address");
        marketingWallet = _newWallet;
        emit MarketingWalletUpdated(_newWallet);
    }

    /**
     * @dev Set token costs for guesses and hints
     * @param _guessCost Cost for a guess
     * @param _hintCost Cost for a hint
     */
    function setCosts(uint256 _guessCost, uint256 _hintCost) external onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused {
        guessCost = _guessCost;
        hintCost = _hintCost;
        emit CostsUpdated(_guessCost, _hintCost);
    }

    /**
     * @dev Admin function to withdraw from jackpot in emergency
     * @param to Recipient address
     * @param amount Amount to withdraw
     */
    function withdrawJackpot(address to, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused {
        require(amount <= jackpotAmount, "Insufficient jackpot");
        jackpotAmount -= amount;
        (bool sent, ) = to.call{value: amount}("");
        require(sent, "Withdraw failed");
    }

    /**
     * @dev Get the current split percentages
     * @return burn, jackpot, next, marketing percentages
     */
    function getSplit() external view returns (uint256, uint256, uint256, uint256) {
        return (burnPercent, jackpotPercent, nextJackpotPercent, marketingPercent);
    }

    /**
     * @dev Get game statistics
     * @return totalGuesses, uniquePlayers, totalWinners, currentJackpot
     */
    function getGameStats() external view returns (uint256, uint256, uint256, uint256) {
        return (totalGuesses, uniquePlayers, totalWinners, jackpotAmount);
    }

    /**
     * @dev Get the current hint
     * @param index Hint index
     * @return Hint text
     */
    function getHint(uint256 index) external view returns (string memory) {
        require(index < hintCount, "Invalid hint index");
        return hints[index];
    }

    /**
     * @dev Helper function to truncate an address to a readable format
     * @param addr The address to format
     * @return Formatted address string
     */
    function _truncateAddress(address addr) internal pure returns (string memory) {
        bytes memory addressBytes = abi.encodePacked(addr);
        bytes memory leadingBytes = new bytes(6);
        bytes memory trailingBytes = new bytes(4);
        
        for(uint i = 0; i < 6; i++) {
            leadingBytes[i] = addressBytes[i + 2]; // Skip '0x'
        }
        
        for(uint i = 0; i < 4; i++) {
            trailingBytes[i] = addressBytes[i + 38]; // Last 4 chars
        }
        
        return string(abi.encodePacked(
            "0x", 
            _toAsciiString(leadingBytes),
            "...",
            _toAsciiString(trailingBytes)
        ));
    }
    
    /**
     * @dev Helper function to convert bytes to ASCII string
     * @param input Bytes to convert
     * @return ASCII string
     */
    function _toAsciiString(bytes memory input) internal pure returns (string memory) {
        string memory output = "";
        for(uint i = 0; i < input.length; i++) {
            uint8 byteValue = uint8(input[i]);
            output = string(abi.encodePacked(output, _byteToAsciiChar(byteValue / 16), _byteToAsciiChar(byteValue % 16)));
        }
        return output;
    }
    
    /**
     * @dev Helper function to convert byte to ASCII character
     * @param value Byte value
     * @return ASCII character
     */
    function _byteToAsciiChar(uint8 value) internal pure returns (string memory) {
        if (value < 10) {
            return string(abi.encodePacked(bytes1(uint8(value + 48))));
        } else {
            return string(abi.encodePacked(bytes1(uint8(value + 87))));
        }
    }
    
    /**
     * @dev Helper function to convert uint to string
     * @param value Integer to convert
     * @return String representation
     */
    function _uintToString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        
        uint256 temp = value;
        uint256 digits;
        
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits--;
            buffer[digits] = bytes1(uint8(48 + (value % 10)));
            value /= 10;
        }
        
        return string(buffer);
    }
    
    /**
     * @dev Pause the game
     */
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /**
     * @dev Unpause the game
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @dev Fallback function for jackpot funding
     */
    receive() external payable {
        revert("Use fundJackpot to add S to the jackpot");
    }
}
