# Pay-per-Play Smart Contract for Games

A Clarity smart contract that enables pay-per-play gaming sessions with automated revenue distribution.

## Overview

This smart contract implements a simple yet powerful pay-per-play system where:
- Players pay 1 STX per gaming session
- Revenue is tracked and distributed
- Session counts are maintained per player
- Contract owner can manage developer addresses

## Contract Details

### Core Functions

#### `start-game-session()`
- Initiates a new gaming session
- Requires 1 STX payment
- Updates player session count

#### `get-player-sessions(player)`
- Returns the number of sessions for a given player

#### `get-play-price()`
- Returns the current price per play (1 STX)

#### `set-developer-address(new-address)`
- Admin function to update developer payment address
- Restricted to contract owner

## Testing

Tests are implemented using Vitest and Clarinet. Run tests with:

`npm run test`

### Test Coverage

- Session creation
- Price verification
- Admin controls
- Payment processing

## CI/CD

GitHub Actions workflow runs:
- Contract syntax validation
- Unit tests
- Automated reporting

## Development

### Prerequisites
- Clarinet
- Node.js v18+
- NPM

### Setup

`npm install`

### Running Tests

`npm run test:report`

## Constants

- PLAY-PRICE: 1 STX (1,000,000 microSTX)
- DEVELOPER-SHARE: 80%
- COMMUNITY-SHARE: 20%

## Future Enhancements

- Multi-game support
- Dynamic pricing
- Time-based sessions
- Player rewards system
- Enhanced revenue sharing
