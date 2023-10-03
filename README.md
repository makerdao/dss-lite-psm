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

`LitePsm` can be thought of as a `Dai<>Gem` pool which aims to stay "perfectly balanced" in the long run. For every
`gem` deposited into `LitePsm`, there should be the same amount of Dai liquidity available, to allow swapping at low
costs in any direction up to the total deposited `gem`. In other words, if there is `100M` `gem` deposited, it should be
possible to buy or sell additional `100M` `gem` without too much gas overhead.

This can be achieved by 2 means:

1. On-band: minting roughly 2x the amount of Dai when users are depositing `gem` through `sellGem`. This is done
   on-the-fly when there is not enough liquidity, which means that the first users or those willing to swap amounts
   larger than the available liquidity will have to bear the additional gas costs that entails this operation.
2. Off-band: whenever the pool is unbalanced because users sold more `gem` than bought it, meaning `gem` liquidity is
   growing, anyone can call `fill`, which will immediately match up the liquidity with newly minted Dai. This role will
   be fulfilled by keeper bots, freeing the users from the gas costs burden, as long as they are swapping within the
   liquidity limits.

The unwinding process is more straightforward, as there is no on-band flow:

1. Off-band: whenever the pool is unbalanced because users bought more `gem` than sold it, meaning the `gem` liquidity
   is decreasing, anyone can call `trim`, which will immediately burn any excess of Dai to match the current `gem`
   liquidity. This role will also be fulfilled by keeper bots.

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
2. Backwards compatibility: the new implementation should not break integrations with the current one.
3. Governance independence: avoid requiring governance intervention to make changes to adjust to expected market
   conditions.
   1. For instance, one of the original ideas was to pre-mint Dai in batches, whose size could be defined by Governance.
      The issue with that approach is that the Governance cycle is way too slow to react to changing market conditions.
4. Permissioned no-fee swaps: specific actors are allowed to use the PSM for swaps without paying any swap fees.
5. Selling large amounts of `gem` for Dai should not revert Dai can be minted on-the-fly to fulfill the request.
    1. Even if this means that the caller will incur in larger gas costs, it is better to complete the swap.
    2. This is an edge case, so it should not happen often, specially when there is high liquidity available.

### Limitations

The Dai liquidity available in this contract is technically unbacked Dai. This is fine most of the time, since the Dai
is locked into this contract until users deposit USDC, backing the amount that is going to be released.

However, during Emergency Shutdown, if there is any outstanding Dai liquidity in this contract, it will be taken in
consideration when collateral backing Dai is distributed pro-rata to Dai holders. Considering that PSMs correspond to a
non-negligible amount of collateral, this should be taken into account if Emergency Shutdown is ever considered.

Worst case scenario happens when the utilization ratio is at 50%, meaning the amount of `gem` deposited into the PSM is
50% of `line` (debt ceiling). In this case, there will be `line / 2` unbacked Dai in the PSM. If the amount of `gem` is
larger than that, the amount of Dai is cannot grow any further because it would surpass `line`. If it is less than that,
the amount of Dai cannot grow permanently beyond the amount of `gem`.

The use of [`AutoLine`][auto-line] for `LitePsm` cannot help alleviate this specific issue. When the utilization is at
50% or above, it means that the existing debt is close to the debt ceiling, which prevents `AutoLine` from acting. If
the utilization is below 50%, the debt will be lower, allowing `AutoLine` to adjust down, but that would bring the
utilization closer to 50% once again.

## Contributing

TODO.

[psm]: https://github.com/makerdao/dss-psm/blob/v2/src/psm.sol
[psm-v2]: https://github.com/makerdao/dss-psm/blob/v2/src/psm.sol
[keg]: ./src/DssKeg.sol
[auto-line]: https://etherscan.io/address/0xc7bdd1f2b16447dcf3de045c4a039a60ec2f0ba3
