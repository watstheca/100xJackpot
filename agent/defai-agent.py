#!/usr/bin/env python3
# ZerePy - DeFAI Agent for 100x Jackpot Game

import os
import json
import time
import asyncio
from datetime import datetime
from web3 import Web3
from dotenv import load_dotenv
from zere import ZereAgent, TaskConfig

# Load environment variables
load_dotenv()

# Configuration
SONIC_RPC_URL = os.getenv("SONIC_RPC_URL", "https://rpc.blaze.soniclabs.com")
JACKPOT_GAME_ADDRESS = os.getenv("JACKPOT_GAME_ADDRESS")
PRIVKEY = os.getenv("PRIVATE_KEY")
TWITTER_API_KEY = os.getenv("TWITTER_API_KEY")
TWITTER_API_SECRET = os.getenv("TWITTER_API_SECRET")
TWITTER_ACCESS_TOKEN = os.getenv("TWITTER_ACCESS_TOKEN")
TWITTER_ACCESS_SECRET = os.getenv("TWITTER_ACCESS_SECRET")

# ABI files
with open("abi/JackpotGame.json", "r") as f:
    JACKPOT_GAME_ABI = json.load(f)

# Initialize Web3
web3 = Web3(Web3.HTTPProvider(SONIC_RPC_URL))
if not web3.is_connected():
    raise Exception(f"Failed to connect to {SONIC_RPC_URL}")

# Initialize contract
jackpot_game = web3.eth.contract(address=JACKPOT_GAME_ADDRESS, abi=JACKPOT_GAME_ABI)

# Initialize agent
agent = ZereAgent(name="100x Jackpot DeFAI", version="1.0.0")

# Event mapping to readable descriptions
EVENT_DESCRIPTIONS = {
    "NEW_SECRET": "A new secret word has been set in the 100x Jackpot game! Can you guess it?",
    "JACKPOT_FUNDED": "The 100x Jackpot just got bigger! More prizes to win!",
    "JACKPOT_WON": "🚨 We have a WINNER! 🚨 Someone just cracked the secret word!",
    "NEW_HINT": "A new hint is available to help you guess the secret word!",
    "LARGE_BATCH": "Just processed a lot of tokens! The jackpot is growing fast!"
}

# Get formatted jackpot amount
async def get_jackpot_info():
    jackpot = jackpot_game.functions.jackpotAmount().call()
    jackpot_s = web3.from_wei(jackpot, 'ether')
    
    total_guesses = jackpot_game.functions.totalGuesses().call()
    unique_players = jackpot_game.functions.uniquePlayers().call()
    
    return {
        "jackpot_s": jackpot_s,
        "total_guesses": total_guesses,
        "unique_players": unique_players
    }

# Tasks

@agent.task
async def monitor_game_events(config: TaskConfig):
    """Monitor events from the 100x Jackpot game contract and react accordingly"""
    
    # Get the latest block number
    latest_block = web3.eth.block_number
    from_block = latest_block - 1000  # Start from 1000 blocks ago, adjust as needed
    
    print(f"Starting event monitoring from block {from_block}")
    
    # Event filters
    social_announcement_filter = jackpot_game.events.SocialAnnouncement.create_filter(fromBlock=from_block)
    guess_committed_filter = jackpot_game.events.GuessCommitted.create_filter(fromBlock=from_block)
    guess_revealed_filter = jackpot_game.events.GuessRevealed.create_filter(fromBlock=from_block)
    jackpot_won_filter = jackpot_game.events.JackpotWon.create_filter(fromBlock=from_block)
    
    # Main monitoring loop
    while True:
        try:
            # Check for social announcements
            social_events = social_announcement_filter.get_new_entries()
            for event in social_events:
                announcement_type = event['args']['announcementType']
                message = event['args']['message']
                
                # Post to Twitter
                await post_to_twitter(announcement_type, message)
                
                # Update the logs
                print(f"[{datetime.now()}] Social Announcement: {announcement_type} - {message}")
            
            # Check for new guesses
            guess_events = guess_committed_filter.get_new_entries()
            for event in guess_events:
                player = event['args']['player']
                print(f"[{datetime.now()}] New guess from {player}")
                
                # Every 10 guesses, post an update
                total_guesses = jackpot_game.functions.totalGuesses().call()
                if total_guesses % 10 == 0:
                    info = await get_jackpot_info()
                    await post_to_twitter(
                        "GUESS_MILESTONE",
                        f"We've reached {total_guesses} guesses from {info['unique_players']} players! "
                        f"Current jackpot: {info['jackpot_s']:.2f} S. Will you be the one to crack the secret?"
                    )
            
            # Check for guess reveals
            reveal_events = guess_revealed_filter.get_new_entries()
            for event in reveal_events:
                player = event['args']['player']
                guess = event['args']['guess']
                won = event['args']['won']
                
                print(f"[{datetime.now()}] Guess revealed by {player}: {guess} (Won: {won})")
                
                # If not a winning guess but interesting word, sometimes comment on it
                if not won and len(guess) > 5:
                    # Post about interesting guesses randomly (about 1 in 5 chance)
                    if hash(guess) % 5 == 0:
                        await post_to_twitter(
                            "INTERESTING_GUESS",
                            f"Someone just guessed '{guess}' - nice try but not the secret word! "
                            f"The jackpot continues to grow! Take a hint and try your luck!"
                        )
            
            # Check for jackpot wins
            win_events = jackpot_won_filter.get_new_entries()
            for event in win_events:
                winner = event['args']['winner']
                amount = web3.from_wei(event['args']['amount'], 'ether')
                guess = event['args']['guess']
                
                print(f"[{datetime.now()}] JACKPOT WON by {winner}! Amount: {amount} S, Secret: {guess}")
                
                # This is already handled by SocialAnnouncement but we could do additional actions here
            
            # Sleep before next check
            await asyncio.sleep(30)  # Check every 30 seconds
            
        except Exception as e:
            print(f"Error in event monitoring: {e}")
            await asyncio.sleep(60)  # Wait a bit longer on error

@agent.task
async def post_to_twitter(announcement_type, message):
    """Post a message to Twitter"""
    try:
        # In a real implementation, we would use Twitter API
        # For this example, we'll just print what would be posted
        
        # Get standard description if available
        description = EVENT_DESCRIPTIONS.get(announcement_type, "")
        
        # Format the tweet
        current_time = datetime.now().strftime("%H:%M:%S")
        hashtags = "\n\n#100xJackpot #SonicNetwork #Blockchain #CryptoGames"
        
        if description:
            tweet = f"{description}\n\n{message}{hashtags}"
        else:
            tweet = f"{message}{hashtags}"
        
        # Trim tweet if too long
        if len(tweet) > 280:
            tweet = tweet[:277] + "..."
        
        print(f"[{current_time}] TWITTER POST: {tweet}")
        
        # In real implementation:
        # api.update_status(status=tweet)
        
        return True
    except Exception as e:
        print(f"Error posting to Twitter: {e}")
        return False

@agent.task
async def daily_jackpot_summary(config: TaskConfig):
    """Post a daily summary of the jackpot stats"""
    while True:
        try:
            # Get current stats
            info = await get_jackpot_info()
            
            # Create summary message
            message = (
                f"📊 Daily 100x Jackpot Update 📊\n\n"
                f"Current Jackpot: {info['jackpot_s']:.2f} S\n"
                f"Total Guesses: {info['total_guesses']}\n"
                f"Unique Players: {info['unique_players']}\n\n"
                f"Will today be the day someone cracks the secret word? "
                f"Buy 100x tokens and take your chance!"
            )
            
            # Post to Twitter
            await post_to_twitter("DAILY_SUMMARY", message)
            
            # Wait for next day (86400 seconds = 24 hours)
            await asyncio.sleep(86400)
            
        except Exception as e:
            print(f"Error in daily summary: {e}")
            await asyncio.sleep(3600)  # Wait an hour on error

@agent.task
async def on_chain_interaction(config: TaskConfig):
    """Perform on-chain interactions when needed"""
    account = web3.eth.account.from_key(PRIVKEY)
    sender_address = account.address
    
    print(f"On-chain agent initialized with address: {sender_address}")
    
    while True:
        try:
            # Check if we need to emit a game update
            current_hour = datetime.now().hour
            
            # Post an engagement message at specific times (e.g., 12 PM and 6 PM)
            if current_hour in [12, 18] and datetime.now().minute < 5:
                # Get current jackpot info
                info = await get_jackpot_info()
                
                # Create an engaging message
                engagement_messages = [
                    f"It's game time! The 100x Jackpot stands at {info['jackpot_s']:.2f} S. Can you guess the secret word?",
                    f"Feeling lucky? Our jackpot is now {info['jackpot_s']:.2f} S! Buy some 100x tokens and make your guess!",
                    f"100x Challenge: Guess the secret word and win {info['jackpot_s']:.2f} S! Hints are available!"
                ]
                
                # Select message based on current day (for variety)
                message_index = datetime.now().day % len(engagement_messages)
                game_update = engagement_messages[message_index]
                
                # Build the transaction
                tx = jackpot_game.functions.emitGameUpdate(game_update).build_transaction({
                    'from': sender_address,
                    'nonce': web3.eth.get_transaction_count(sender_address),
                    'gas': 200000,
                    'gasPrice': web3.eth.gas_price
                })
                
                # Sign and send the transaction
                signed_tx = web3.eth.account.sign_transaction(tx, PRIVKEY)
                tx_hash = web3.eth.send_raw_transaction(signed_tx.rawTransaction)
                
                print(f"[{datetime.now()}] Sent game update: {game_update}")
                print(f"Transaction hash: {tx_hash.hex()}")
                
                # Wait 3 hours before checking again
                await asyncio.sleep(10800)
            else:
                # Check every 15 minutes
                await asyncio.sleep(900)
                
        except Exception as e:
            print(f"Error in on-chain interaction: {e}")
            await asyncio.sleep(3600)  # Wait an hour on error

# Main function
async def main():
    print("Starting 100x Jackpot DeFAI Agent...")
    
    # Start all tasks
    await asyncio.gather(
        monitor_game_events(TaskConfig()),
        daily_jackpot_summary(TaskConfig()),
        on_chain_interaction(TaskConfig())
    )

if __name__ == "__main__":
    # Run the agent
    agent.run(main)
