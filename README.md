# 🌾 Yieldbit - Agro Yield Token

A blockchain-based agricultural tokenization platform that backs digital tokens with verified seasonal harvests. Built on Stacks using Clarity smart contracts.

## 🎯 Overview

Yieldbit connects farmers with investors by tokenizing agricultural yields. Farmers register their harvests, get them verified, and receive tokens proportional to their yield. Token holders benefit from the agricultural productivity backing their digital assets.

## ✨ Features

- 🚜 **Farmer Registration**: Farmers can register and build reputation
- 🌱 **Harvest Reporting**: Report seasonal harvests with yield amounts and crop types  
- ✅ **Harvest Verification**: Verified farmers and contract owner can verify harvests
- 🪙 **Token Minting**: Verified harvests automatically mint YBT tokens
- 🔄 **Token Transfers**: Standard ERC-20 style token functionality
- 📊 **Seasonal Tracking**: Automatic season progression and statistics
- 💰 **Token Purchase**: Buy tokens directly with STX
- 📈 **Reputation System**: Farmers build reputation through verified harvests

## 🏗️ Contract Architecture

### Core Components

- **Token Management**: Standard token functionality (transfer, approve, allowances)
- **Farmer System**: Registration, reputation tracking, harvest counting
- **Harvest Verification**: Multi-step verification process with reputation requirements
- **Seasonal Cycles**: Automatic season progression every ~52,560 blocks (~1 year)
- **Statistics Tracking**: Season-by-season yield and token distribution data

### Key Constants

- `TOKEN_NAME`: "Yieldbit"
- `TOKEN_SYMBOL`: "YBT" 
- `TOKEN_DECIMALS`: 6
- `BLOCKS_PER_SEASON`: 52,560 (approximately 1 year)

## 🚀 Usage

### For Farmers

1. **Register as a Farmer**
   ```clarity
   (contract-call? .Yieldbit register-farmer)
   ```

2. **Report a Harvest**
   ```clarity
   (contract-call? .Yieldbit report-harvest u1000 "corn")
   ```

3. **Check Your Info**
   ```clarity
   (contract-call? .Yieldbit get-farmer-info tx-sender)
   ```

### For Verifiers

1. **Verify a Harvest** (requires verification permissions)
   ```clarity
   (contract-call? .Yieldbit verify-harvest 'SP1... u1 u1)
   ```

### For Token Holders

1. **Check Balance**
   ```clarity
   (contract-call? .Yieldbit get-balance tx-sender)
   ```

2. **Transfer Tokens**
   ```clarity
   (contract-call? .Yieldbit transfer u100 'SP2...)
   ```

3. **Purchase Tokens**
   ```clarity
   (contract-call? .Yieldbit purchase-tokens u10)
   ```

### For Contract Owner

1. **Advance Season** (when season period ends)
   ```clarity
   (contract-call? .Yieldbit advance-season)
   ```

## 📊 Data Structures

### Farmers Map
- `registered`: Boolean registration status
- `total-harvests`: Number of reported harvests
- `reputation-score`: Score from 0-100 based on verified harvests
- `last-harvest-block`: Block height of last harvest report

### Harvests Map
- `yield-amount`: Quantity of harvest in base units
- `crop-type`: String identifier for crop type
- `verified`: Boolean verification status
- `verification-block`: Block when verified
- `verifier`: Principal who verified the harvest
- `tokens-issued`: Amount of tokens minted for this harvest

### Season Stats Map
- `total-yield`: Cumulative yield for the season
- `total-farmers`: Number of active farmers
- `tokens-distributed`: Total tokens minted in season
- `harvest-count`: Number of harvests reported
- `season-end-block`: Block when season ended

## 🔐 Access Control

- **Contract Owner**: Can verify harvests and advance seasons
- **Verified Farmers**: Can verify other farmers' harvests (reputation ≥75)
- **Registered Farmers**: Can report harvests
- **Token Holders**: Can transfer and trade tokens

## 💡 Token Economics

- **Harvest Tokens**: 100 YBT per unit of verified yield
- **Purchase Rate**: 1,000 YBT per 1 STX
- **Verification Required**: Only verified harvests mint tokens
- **Reputation Impact**: Failed verifications reduce farmer reputation

## 🌐 Read-Only Functions

- `get-name()`: Returns token name
- `get-symbol()`: Returns token symbol  
- `get-decimals()`: Returns decimal places
- `get-total-supply()`: Returns total token supply
- `get-balance(principal)`: Returns token balance
- `get-current-season()`: Returns current season number
- `get-farmer-info(principal)`: Returns farmer data
- `get-harvest-info(farmer, season, harvest-id)`: Returns harvest details
- `get-season-stats(season)`: Returns season statistics
- `is-season-active()`: Returns if current season is active

## 🔄 Error Codes

- `u100`: Not authorized
- `u101`: Not found
- `u102`: Already exists
- `u103`: Invalid amount
- `u104`: Insufficient balance
- `u105`: Harvest not verified
- `u106`: Season not active
- `u107`: Invalid season

## 🛠️ Development

### Prerequisites
- Clarinet CLI
- Node.js (for testing)

### Testing
```bash
clarinet test
```

### Deployment
```bash
clarinet deploy
```

## 📝 License

MIT License - see LICENSE file for details

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Submit a pull request with clear description

---

💚 sustainable agriculture and blockchain innovation

















