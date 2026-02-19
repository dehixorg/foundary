##  Freelancer Trust Protocol

A decentralized smart contract system that enables secure collaboration between business owners and freelancers using blockchain-based agreements, staking, and soulbound reputation tokens.

##  Overview

Freelancer Trust Protocol is a Web3-based platform designed to:

- Create on-chain Non-Disclosure Agreements (NDAs)
- Enable secure collaboration between business owners and freelancers
- Provide staking-based incentives
- Issue non-transferable reputation tokens (SoulBound Tokens)
- Increase trust and transparency in freelance work

##  Smart Contracts

- FreelancerContract
- StakingRewards
- MyToken (Platform Token)
- NDASoulBoundToken
- FreelancerSoulBoundToken

##  Network

Currently deployed on:
- BNB Smart Chain Testnet (Chain ID: 97)
##  Security

- AccessControl-based permissions
- Soulbound token restrictions
- Reentrancy protection
- Role-based authorization
- Lifecycle state management

## 🗺 Roadmap

See `docs/PROJECT.md` for roadmap and impact.

##  Setup

See `docs/TECHNICAL.md` for full setup instructions.



### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
