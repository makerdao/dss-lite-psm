# `dss-lite-psm`

Lightweight Peg Stability Module (PSM) implementation.

## Table of Contents

<!-- vim-markdown-toc GFM -->

- [Deployments](#deployments)
- [Overview](#overview)
- [Architecture](#architecture)
  - [Design and Constraints](#design-and-constraints)
  - [Limitations](#limitations)
- [Contributing](#contributing)

<!-- vim-markdown-toc -->

## Deployments

- Mainnet: \[TBD\]
- Goerli: \[TBD\]

## Overview

A PSM is a facility through which users can freely swap Dai for stablecoins with no slippage. MakerDAO Governance can
enable swap fees, though, which are computed as revenue for the protocol.

This module is heavily inspired in the [original PSM][psm], [the current PSM v2][psm-v2] and some other PSM prototypes
within MakerDAO repositories.

The issue with those PSM implementations is that swapping through them can be quite gas intensive, because they
manipulate the `Vat` (MakerDAO's main accounting module) directly on every swap.

To help alleviate this problem, `LitePsm` aims to be more gas efficient. The strategy is to allow users to swap in a
**pool** of pre-minted Dai and stablecoins, reducing the base case of a swap to 2 ERC-20 token transfers with little
overhead. The bookkeeping part is mostly done _off-band_ (not to be confused with _off-chain_), through a set of
permissionless functions that aim to rebalance the pool and incorporate the accumulated swap fees into the protocol's
surplus buffer.

Furthermore, there is a new requirement related to MakerDAO Endgame to allow authorized parties to swap through the PSM
without paying any fees, even if they have been activated by Governance. Apart from the existing permissionless `buyGem`
/ `sellGem` functions, this iteration introduces `buyGemNoFee` / `sellGemNoFee` permissioned counterparties.

Last, but not least, in this version the `gem` balance **can** be held in a different address to allow the protocol to
receive yield from stablecoins that require the custody of the assets to be segregated. This address can be either an
orphaned EOA or an instance of [`DssKeg`][keg] &ndash; an airtight container for `gem` &ndash; a novel smart contract.
The only constraint is that `LitePsm` **should** be able to freely move any amount of `gem` on behalf of such address.

TODO.

## Architecture

A simplified diagram of the `LitePsm` architecture:

```
                                            buyGemNoFee /            O
                                      ┌───────────────────────────  -|-
                                      │     sellGemNoFee            / \
                                      │
                                      │                         Whitelisted
                                      │                            User
                                      │
                                      │
                                      │
                                      │
                                      │
┌─────────┐    gem.approve     ┌──────▼──────┐
│         ├────────────────────►             │     buyGem /           O
│   Keg   │                    │   LitePsm   ◄─────────────────────  -|-
│         ◄────────────────────┤             │     sellGem           / \
└─────────┘  gem.transferFrom  └──────▲──────┘
                                      │                              User
                                      │
                                      │
                                      │
                                      │
                                      │                               O
                                      │   fill / trim / gulp         -|-
                                      └───────────────────────────   / \

                                                                    Keeper
```

### Design and Constraints

These are the main constraints that guided the design of this module:

1. Gas efficiency: make swaps as cheap in terms of gas as possible, without sacrificing security and readability.
1. Backwards compatibility: the new implementation should not break integrations with the current one.
1. Permissioned no-fee swaps: specific actors are allowed to use the PSM for swaps without paying any swap fees.
1. Selling large amounts of `gem` for Dai should not revert Dai can be minted on-the-fly to fulfill the request.
    1. Even if this means that the caller will incur in larger gas costs, it is better to complete the swap.
    1. This is an edge case, so it should not happen often, specially when there is high liquidity available.

### Limitations

The Dai liquidity available in this contract is technically unbacked Dai. This is fine most of the time, since the Dai
is locked into this contract until users deposit USDC, backing the amount that is going to be released.

Also notice that this implementation completely disregards Emergency Shutdown. This is intentional, as it complicates a
lot the design.

## Contributing

TODO.

[psm]: https://github.com/makerdao/dss-psm/blob/v2/src/psm.sol
[psm-v2]: https://github.com/makerdao/dss-psm/blob/v2/src/psm.sol
[keg]: ./src/DssKeg.sol
[auto-line]: https://etherscan.io/address/0xc7bdd1f2b16447dcf3de045c4a039a60ec2f0ba3
