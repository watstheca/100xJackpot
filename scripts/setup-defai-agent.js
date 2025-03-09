// Script to configure the DeFAI agent integration
const hre = require("hardhat");

async function main() {
  console.log("Configuring DeFAI agent integration...");
  
  // Get addresses from previous deployments
  const jackpotGameAddress = process.env.JACKPOT_GAME_ADDRESS || "0x0000000000000000000000000000000000000000";
  const defaiAgentAddress = process.env.DEFAI_AGENT_ADDRESS || "0x0000000000000000000000000000000000000000";
  
  if (jackpotGameAddress === "0x0000000000000000000000000000000000000000") {
    console.error("Please set the JACKPOT_GAME_ADDRESS environment variable!");
    process.exit(1);
  }
  
  // Get the contract deployer account
  const [deployer] = await hre.ethers.getSigners();
  console.log("Configuring with account:", deployer.address);
  
  // Get the JackpotGame contract instance - using fully qualified name
  const jackpotGame = await hre.ethers.getContractAt("contracts/JackpotGameSlim.sol:JackpotGame", jackpotGameAddress);
  
  // If no agent address is provided, we'll use the deployer address temporarily
  const agentAddress = defaiAgentAddress === "0x0000000000000000000000000000000000000000" 
    ? deployer.address 
    : defaiAgentAddress;
  
  console.log("Setting DeFAI agent address:", agentAddress);
  
  // Check if the agent is already set
  try {
    const currentAgent = await jackpotGame.defaiAgent();
    if (currentAgent.toLowerCase() === agentAddress.toLowerCase()) {
      console.log("DeFAI agent already set correctly.");
    } else {
      console.log("Current agent address:", currentAgent);
      console.log("Setting to:", agentAddress);
      
      // Set the DeFAI agent address
      const txAgent = await jackpotGame.setDefaiAgent(agentAddress);
      await txAgent.wait();
      console.log("DeFAI agent address updated. Tx hash:", txAgent.hash);
    }
  } catch (error) {
    console.log("Error checking defaiAgent, might not exist in slimmed contract:", error.message);
    console.log("Continuing with setup...");
  }
  
  // Add some initial hints for the game
  console.log("Adding some initial hints...");
  const hints = [
    "The secret is a common word in English.",
    "The secret has less than 10 letters.",
    "The secret is related to blockchain technology."
  ];
  
  // Check if we already have hints
  let hintCount = 0;
  try {
    hintCount = await jackpotGame.hintCount();
    console.log("Current hint count:", hintCount);
  } catch (error) {
    console.log("Error checking hintCount, might have different implementation:", error.message);
  }
  
  if (hintCount.toString() === "0") {
    for (let i = 0; i < hints.length; i++) {
      console.log(`Adding hint #${i}: ${hints[i]}`);
      try {
        const txHint = await jackpotGame.addHint(hints[i]);
        await txHint.wait();
        console.log(`Hint #${i} added. Tx hash:`, txHint.hash);
      } catch (error) {
        console.log(`Error adding hint #${i}:`, error.message);
      }
    }
  } else {
    console.log("Hints already exist. Skipping hint addition.");
  }
  
  // Setting a sample secret for the game
  // In a real-world scenario, this would be a more carefully chosen secret
  const secret = "ethereum";
  const salt = hre.ethers.randomBytes(32); // Generate a random salt
  
  // Create the secret hash - in production, you'd want to do this offline
  // to keep the secret more secure
  const secretHash = hre.ethers.keccak256(
    hre.ethers.concat([
      hre.ethers.toUtf8Bytes(secret),
      salt
    ])
  );
  
  console.log("Setting a sample secret for the game...");
  console.log("Secret (for testing only):", secret);
  console.log("Salt:", salt);
  console.log("Secret Hash:", secretHash);
  
  // Set the secret hash in the contract
  try {
    const txSecret = await jackpotGame.setSecretHash(secretHash, salt);
    await txSecret.wait();
    console.log("Secret hash set. Tx hash:", txSecret.hash);
  } catch (error) {
    console.log("Error setting secret hash:", error.message);
  }
  
  // Emit a game update to test the DeFAI integration
  try {
    console.log("Emitting a test game update...");
    const txUpdate = await jackpotGame.emitGameUpdate("The 100x Jackpot game is now live! Try to guess the secret and win the jackpot!");
    await txUpdate.wait();
    console.log("Game update emitted. Tx hash:", txUpdate.hash);
  } catch (error) {
    console.log("Error emitting game update:", error.message);
    console.log("This function might not exist in the slimmed-down contract.");
  }
  
  console.log("\n====== DEFAI INTEGRATION SETUP COMPLETE ======");
  console.log("JackpotGame:", jackpotGameAddress);
  console.log("DeFAI Agent:", agentAddress);
  console.log("Test Secret:", secret); // In production, don't log this!
  console.log("==============================================\n");
  
  console.log("Next steps:");
  console.log("1. Implement a ZerePy agent that listens to events from the contract");
  console.log("2. Configure the agent to post on social media when events occur");
  console.log("3. Test the full flow by making guesses and triggering events");
}

// Execute the setup
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });