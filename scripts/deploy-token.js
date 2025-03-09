// Script to deploy the Token100x contract
const hre = require("hardhat");

async function main() {
  console.log("Deploying Token100x to Sonic network...");
  
  // Get the contract deployer account
  const [deployer] = await hre.ethers.getSigners();
  console.log("Deploying with account:", deployer.address);
  console.log("Account balance:", (await hre.ethers.provider.getBalance(deployer.address)).toString());

  // Deploy Token100X contract
  const Token100x = await hre.ethers.getContractFactory("Token100x");
  const token100x = await Token100x.deploy();
  
  // Wait for the deployment to complete
  await token100x.deploymentTransaction().wait();
  const tokenAddress = await token100x.getAddress();

  console.log("Token100x deployed to:", tokenAddress);
  console.log("Token supply: 1,000,000,000 100x (with 6 decimals)");
  
  // Verify the balance of the deployer
  const balanceOf = await token100x.balanceOf(deployer.address);
  console.log("Deployer token balance:", balanceOf.toString());
  
  // Save the contract addresses for use in subsequent deployments
  console.log("Please save this address for the next deployment step!");
  console.log("Token100x address:", tokenAddress);
  
  // Log the info needed for contract verification (if needed later)
  console.log("To verify on block explorer:");
  console.log(`npx hardhat verify --network sonicTestnet ${tokenAddress}`);
}

// Execute the deployment
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
