# `dss-lite-psm`

Lightweight Peg Stability Module (PSM) implementation.

## Table of Contents

<!-- vim-markdown-toc GFM -->

- [Deployments](#deployments)
- [Overview](#overview)
- [Architecture](#architecture)
  - [Design and Constraints](#design-and-constraints)
  - [Known Limitations](#known-limitations)
    - [1. Potential Front-Running](#1-potential-front-running)
    - [2. No Slippage Protection](#2-no-slippage-protection)
    - [3. No Support for Upgradeable Gems](#3-no-support-for-upgradeable-gems)
    - [4. Emergency Shutdown](#4-emergency-shutdown)
- [Contributing](#contributing)

<!-- vim-markdown-toc -->

## Deployments

- Mainnet: \[TBD\]
- Goerli: \[TBD\]

## Overview

A Peg Stability Module (PSM) is a facility through which users can freely swap Dai for stablecoins with no slippage.
MakerDAO Governance can enable swap fees, though, which are computed as revenue for the protocol.

This module is heavily inspired by the [current PSM][psm], [PSM v2][psm-v2] and some other PSM prototypes within
MakerDAO repositories.

The issue with those implementations is that swapping through them can be quite gas intensive, because they manipulate
the `Vat` (MakerDAO's main accounting module) directly on every swap.

To help alleviate this problem, `DssLitePsm` aims to be more gas efficient. The strategy is to allow users to swap in a
**pool** of pre-minted Dai and stablecoins, reducing the swap to 2 ERC-20 token transfers with little overhead.

The required bookkeeping is done _off-band_ (not to be confused with _off-chain_), through a set of permissionless
functions that aim to keep the pool operating under the predefined constraints, and incorporate the accumulated swap
fees into the protocol's surplus buffer.

Furthermore, there is a new requirement &ndash; related to MakerDAO Endgame &ndash; to allow authorized parties to swap
through the PSM without paying any fees, even if they have been activated by Governance. Apart from the existing
permissionless `buyGem` / `sellGem` functions, this iteration introduces `buyGemNoFee` / `sellGemNoFee` permissioned
counterparties.

Last, but not least, in this version `gem` balance **can** be held in a different address to allow the protocol to
receive yield from stablecoins that require the custody of the assets to be segregated. This address can be either an
orphaned EOA or an instance of [`DssPocket`][pocket] &ndash; a container for `gem` &ndash; a novel smart contract.  The
only constraint is that `DssLitePsm` **should** be able to freely move any amount of `gem` on behalf of such address.

## Architecture

A simplified diagram of the `DssLitePsm` architecture:

```
                                                buyGemNoFee /
                                           ╭────────────────────────  🤴
 ╭─────────╮                               │    sellGemNoFee      Whitelisted
 │         │       transferFrom            │                         User
 │   Gem   ◄────────────────────────────╮  │
 │         │                            │  │
 ╰────▲────╯                            │  │
      │                                 │  │
      │                                 │  │
      │ approve ·····╮                  │  │
      │              ╎                  │  │
╭─────┴────╮         ╎          ╭───────┴──▼───╮
│          │         ╎          │              │     buyGem /
│  Pocket  │         ╰·········>│  DssLitePsm  ◄────────────────────  🧑
│          │                    │              │     sellGem         User
╰──────────╯                    ╰─┬──┬──┬──▲───╯
                                  │  │  │  │
                                  │  │  │  │
              slip / frob         │  │  │  │
     ╭────────────────────────────╯  │  │  │
     │                               │  │  │
     │                               │  │  │
     │                               │  │  │   fill / trim / chug
     │                   join / exit │  │  ╰────────────────────────  👷
     │                               │  │                           Keeper
     │                               │  │
╭────▼────╮          ╭───────────╮   │  │
│         │   move   │           │   │  │
│   Vat   ◄──────────┤  DaiJoin  ◄───╯  │
│         │          │           │      │
╰─────────╯          ╰─────┬─────╯      │
                           │            │
                           │            │
               mint / burn │            │
                           │            │ transfer / transferFrom
                           │            │
                      ╭────▼────╮       │
                      │         │       │
                      │   Dai   ◄───────╯
                      │         │
                      ╰─────────╯
```

### Design and Constraints

These are the main constraints that guided the design of this module:

1. Gas efficiency: make swaps as cheap in terms of gas as possible, without sacrificing security and readability.
1. Backwards compatibility: the new implementation should not break integrations with the current one.
1. Permissioned no-fee swaps: specific actors are allowed to use the PSM for swaps without paying any swap fees.

Part of the Dai liquidity available in `DssLitePsm` is technically unbacked Dai. This not a problem because the Dai is
locked into `DssLitePsm` until users deposit USDC, backing the amount that is going to be released.

### Known Limitations

#### 1. Potential Front-Running

`DssLitePsm` relies on pre-minted Dai. It is designed to keep a fixed-sized amount (`buf`) of it available most of the
time.  However, when users call `buyGem`, the amount of Dai available will be temporarily larger than `buf`.

**Scenario A:** a user might observe the outstanding amount of Dai and wish to call `sellGem` to receive the total of
Dai in return. In that scenario, there is a possibility of a transaction calling any of the permissionless bookkeeping
functions to front-run them, causing the swap to fail, as the Dai liquidity would be lower than the required amount.

The scenario A above is not possible with the current PSM implementation because each swap is "self-balancing", so no
off-band bookkeeping is required.

**Scenario B:** a large swap might front-run another one, even if unintentionally. Imagine there is `10M` Dai
outstanding in `DssLitePsm`. If Alice &ndash; who wants to swap `8M` &ndash; and Bob &ndash; who wants to swap `3M`
&ndash; submit their transactions at the same time, only the first one will be executed.

The scenario B above is not possible with the current PSM implementation because `sellGem` is able to mint Dai
on-the-fly to fulfill the swap, given that there is enough room in the debt ceiling.

Notice how the same issue happens in `buyGem`, however the amount of `gem` deposited into `DssLitePsm` is only bounded
by the debt ceiling, while the amount of `Dai` will tend to gravitate towards `buf`.

The consequence is that anyone willing to call `sellGem` with a value larger than `buf` should take care of potential
front-running transactions by bundling it with an optional liquidity increase (`fill`).

#### 2. No Slippage Protection

Swaps in `DssLitePsm` are generally not subject to slippage. The only exception is when there is a MakerDAO Governance
proposal do increase the swapping fees `tin` and `tout`. That is done through an Executive Spell, which is an on-chain
smart contract that can be permissionlessly _cast_ (executed) after following the Governance process.

If Alice sends a swap transaction and a spell increasing the fees is cast before her transaction, she will either pay
more Dai when buying gems or receive less Dai when selling gems than the originally expected.

This is a highly unlikely scenario, but users or aggregators are able to handle this issue through a wrapper contract.

#### 3. No Support for Upgradeable Gems

We no longer have a dedicated `GemJoin` contract to normalize different token implementations. For instance, we lost the
capacity to identify upgrades in upgradeable tokens when compared to the previous iteration of the [PSM][gem-join-8].

On the other hand, non-upgradeable gems that [do not return `true` on `transfer`/`transferFrom`][weird-erc20] were not
previously supported, but we removed such restriction in this iteration.


#### 4. Emergency Shutdown

`DssLitePsm` assumes the ESM threshold is set large enough prior to its deployment, so Emergency Shutdown can never be
called.

## Contributing

To be able to run the integration tests, you need to set the `ETH_RPC_URL` env var to a valid Mainnet node:

```bash
ETH_RPC_URL='...' forge test -vvv
```

You can also use a `.env` file for that (see `.env.example`):

```bash
# .env
ETH_RPC_URL='...'
```

Then simply run:
```bash
forge test -vvv
```


[psm]: https://github.com/makerdao/dss-psm/blob/v2/src/psm.sol
[psm-v2]: https://github.com/makerdao/dss-psm/blob/v2/src/psm.sol
[pocket]: ./src/DssPocket.sol
[auto-line]: https://etherscan.io/address/0xc7bdd1f2b16447dcf3de045c4a039a60ec2f0ba3
[gem-join-8]: https://github.com/makerdao/dss-psm/blob/master/src/join-8-auth.sol#L36
[weird-erc20]: https://github.com/d-xo/weird-erc20/#missing-return-values
