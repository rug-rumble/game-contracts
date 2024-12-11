# RugRumble

RugRumble is a card based game where players can wager meme tokens in head-to-head battles. The game utilizes smart contracts to manage game logic, token swaps, and a vault system for distributing rewards.

### Smart Contracts

- **RugRumble.sol** : Main contract for managing game logic and token swaps.
The Game Contract is responsible for managing individual games between two players, including handling player wagers, NFT locking/unlocking, and determining the winner based on game logic. The contract interacts with the Vault Contract to deposit a portion of the loser's tokens into the vault and facilitates the swapping of tokens between players and the vault.
- **RugRumbleNFT.sol** - Contract for managing NFTs and player collections.
- **RugRumbleVault.sol** : Contract for managing rewards and distributing tokens to players.
Main purpose of vault contract is to act as ‘memery’ where 30% of the tokens from the losing player per game will come (After swapping to the winning token). At the end of each epoch, all tokens are converted to the highest value token, and distributed to players of the winning meme coin.

#### Contracts to handle

1. **Meme Token Wagering**: Players can wager various supported meme tokens.

2. **NFT Integration**: Players must lock NFT cards to participate in games.

3. **Token Swapping**: Automatic token swaps are performed using DEX adapters.

4. **Epoch-based Rewards**: Rewards are distributed at the end of each epoch based on the best-performing meme token.

5. **Admin Controls**: Admin functions for managing supported tokens, epochs, and game settings.

### Game Flow

- Admin/Backend sets up a game with two players, specifying tokens and wager amounts for that gameId.

- Players deposit their wagers and lock their NFT decks.

- The game concludes (off-chain logic determines the winner).

- Admin/Backend calls the endGame function to distribute rewards.

- Tokens are swapped and distributed:
  - 69% to the winner
  - 30% to the Vault
  - 1% as platform fees

5. NFTs are unlocked for both players.

6. At the end of an epoch, the Vault settles all collected tokens and distributes rewards to players who wagered the winning token.

### Installation

```bash
forge install
```

### Usage

```bash
forge build
```

### Testing

```bash
forge test
```
