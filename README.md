*Update Sept 19, 2020: so there's this thing called flash loans now that are kind of a big deal*

# Planck
Planck is a speculative proof-of-concept/thought experiment for a sub-transaction liquidity protocol on Ethereum. 

Can you "safely" allow unlimited, unchecked, and uncollateralized loans on the time-scale of a single transaction? If so, would there be a demand? Where would all that liquidity come from? This project explores the technical viability and potential incentive structures of such a system.

###### Disclaimers
1. The proof of concept contracts are untested and unaudited. 
2. It leans heavily on smart contract logic that would be considered an anti-pattern in all but (and maybe including) this specific implementation.
3. Permissionless access to unlimited liquidity could definitely be used for evil. 
4. Use, modify, or deploy freely but at your own risk.

### Overview

###### Flash Boys/Bots

With the explosion of "DeFi" applications on the Ethereum network, an increasingly sophisticated group of actors are competing for new profit opportunities. These users automate complex smart contract actions, monitor pending transactions, and compete with one another to maximize profits. These arbitragers, liquidators, and opportunists continually look for every new edge possible within the limits of the network. In this arms race, efficient access to liquidity is a huge advantage.

###### Atomic Loans

Planck is an open protocol that allows anyone to borrow ether. It offers instant, unrestricted, uncollateralized loans. The only requirement is that loans are repaid in full, plus a small fee, in the same transaction. The maximum duration of a Planck loan is the smallest conceptual unit of time in Ethereum: the length between two calls in the same transaction. Planck loans are either borrowed and repaid in full, or completely reversed.

###### Automated Interest 

Anyone can provide liquidity to the Planck system and remove it at any time. Liquidity is represented by shares of a proportional amount of the total value held by the protocol. Shares grow in relative value when fees are collected from loan repayments. Shares can be traded, transferred, and used in other protocols without restriction. 

###### Stance on "Decentralization"

Planck has no owners, administrators, or privileged access. It is not a company, organization, or foundation. The only fees collected go to liquidity providers. It does not have an off switch, a pause button, or a path to upgradability. 

### Design Decisions

###### If This, Then That
Planck relies on a core value proposition of Ethereum: the deterministic, sequential execution a specific set of operations. In short the logic of a Planck loan is:

1. Record initial value.
2. Transfer value.
3. ...(anything can happens here)... 
4. At the end of execution: compare current value with initial value. Revert if lower than expected.

In practice, however, smart contract execution isn't always so predicable. It is entirely possible there are EVM gotchas, undetected edge cases, or simple user errors that render Planck useless or catastrophically vulnerable.

###### call.value() ?!

Yes, that's right. Planck not only uses an unchecked `call.value()`, but also exposes it to anyone, and will happily transfer the full contract balance. This is near-universally described as "bad practice". However, it is viable (with many caveats) because of the single transaction duration of a Planck loan. 

Since EIP-150, raw calls reserve 1/64th of the available gas to complete execution. This allows the `borrow()` function, no matter what the borrower does in the interim, to reach a `require` statement that guarantees the atomicity of the loan. To be safe, Planck reserves a little extra gas just in case. The call is sent with no data, requiring the borrower to trigger some logic from a fallback function in their contract. Effectively, this works like `transfer()` but passes more gas (up to a maximum of the remaining gas in the block). 

### Borrowers in Detail

###### No Questions Asked

A borrower is any actor who wishes to use Planck's liquidity. They can borrow any amount up to 100% of the total value in the system. They do not have to provide collateral or demonstrate credit-worthiness. There are no restrictions on how the funds are used during the term of the loan. The only condition is that they must return the amount borrowed, plus a fee (likely on the order of 0.3%), within the same transaction. 

###### "User Friendly"

Because of the intra-tranaction nature of the system only contracts can borrow from Planck. Initial borrowers will likely be sophisticated users capable of writing smart contracts and automating actions on the Ethereum network. Anyone who currently uses GasToken, for example, meets the technical threshold to use Planck. Weird protocol quirks/experiments like GasToken are now near essential requirements in competitive arbitrage/trading.

###### Schrödinger's Loan

A borrower requests a loan by calling the Planck contract and specifying an amount. This amount (plus interest) is temporarily stored in a mapping of outstanding debt keyed to the borrower's address. Funds are then transferred via raw call, allowing the borrower to trigger any set of actions within or outside of their own contract. Repayment is enforced by requiring the Planck contract's balance be equal or greater to the initial value by the time the original `borrow()` function completes execution. If the debt is not returned by this point, the entire transaction reverts. At a high level, loans are either repaid in full with interest, or they never happened at all. 

###### Some Tiny Restrictions Apply

There are several technical restrictions on borrowing that ensure the security of the system. 1) Globally, there can only be one outstanding loan at any given time. However, many sequential loans can be issued and repaid in the same block or even the same transaction. 2) Loans must be repaid in full, though not necessarily from the original `msg.sender`. 3) Adding/withdrawing liquidity is temporarily paused during the term of the loan. 

### Liquidity Providers in Detail

###### Open Liquidity

Planck's version of open liquidity works a lot like Uniswap. Anyone can provide liquidity at any time. In return, they are issued tokenized shares that represent the proportion of the total liquidity they are entitled to. For example: Bob provides 100 ETH in liquidity, bringing the total pool to 1000 ETH. Enough shares are minted so that he Bob receives 10% of the new total share supply. In this example, he would receive 90 shares representing 10% of the global supply. x% of shares are always redeemable for x% of liquidity. 

###### Rent Sharing, Not Rent Seeking

All fees collected from loans are added to the total available liquidity. Thus, each share increases in relative value (eg, Bob still has 10% of the shares, but is entitled to 10% of a larger pie). In an economically rational system, the demand for and willingness to provide liquidity would approach some kind of equilibrium between risk/reward and supply/demand.

###### Hypothetical Rehypothecation

Shares can be burned/redeemed in exchange for their proportional value from the liquidity pool. Share value relative to the initial liquidity provided can only increase (or in the event of zero fees, remain the same). Shares can also be transferred, traded, and used in other protocols (note: not in the proof of concept contracts). Hypothetically, Planck providers could generate interest from multiple protocols at once via tokenized abstraction (a PlanckToken/cETH Uniswap pool is only the beginning...).

### Security Considerations

###### Reentrancy

To prevent a variety of attack vectors, a global mutex is set within the `borrow()` function before any value is transferred. It is only unlocked if the loan is returned (or is reverted to its initial state). While the mutex is active, all functions with the exception of `repayDebt()` are paused at a global level. This prevents simple reentrancy as well as manipulation of liquidity shares with borrowed funds. Other users are unaffected by the mutex as it is only active for a portion of a single transaction.

###### Call Stack Depth 

Call stack depth attacks are apparently no longer possible as of EIP-150. 

###### Denial of Service

There is a limited denial of service vector in Planck. A malicious user could borrow a loan for a full block. This would require them to pay a high enough gas fee to take up all, or a sizeable amount, of the block's computation. The loan amount is not relevant in this scenario as no fees would be generated if the loan transaction reverts by design. Effectively, this is a block stuffing attack and would effect all users at the network level. The attacker would have to pay high gas fees to sustain this attack. 

###### Protocol Level Changes

Planck is 100% dependent on specific assumptions about opcode gas pricing, address properties, block size, call sequencing, and other factors. These only hold true in the implementation of the current Ethereum protocol. Future network forks that alter these or other variables may break Planck.

###### Forced Ether

Planck relies heavily on referencing the balance of its own address rather than needlessly updating available liquidity in storage. However, outstanding debt is mapped in storage prevent to a specific forced ether attack. The conditions for successful loan repayment requires the borrower's debt to be 0 in storage. This prevents a malicious borrower forcibly sending ether via `self.destruct` and "tricking" the contract into thinking the loan is repaid without unlocking the mutex. The gas cost of this extra storage write is mitigated by the refund for writing it back to zero in the same transaction.

###### Rounding Errors

There may be some undiscovered edge cases related to share supply when liquidity is at or near zero. Planck relies heavily on calculating proportions of parts to a whole. All that division may introduce some rounding errors, with underexplored consequences.  

### Use Cases for Short-Term Liquidity

###### Arbitrage

An obvious use case for Planck is arbitrage between decentralized exchanges, where large amounts of liquidity are needed for short times at unpredictable intervals. For example, when a price discrepancy arrises after a large Uniswap trade, a variety of automated accounts race to buy/sell from another dex and buy/sell back to Uniswap within a single complex smart contract transaction. They are guaranteed to be profitable or, at worst, burn a small amount of gas from a reverted transaction. 

###### Liquidation

Open and open-ish lending protocols like MakerDao, Compound, dYdX, etc, incentivize adequate collateralization in their systems by rewarding external actors. These "keepers" are rewarded for their ability to quickly inject liquidity in the system by liquidating unsafe loans.  

###### Underhanded Voting/Signalling

Any non-time locked, non-sybil resistant, voting/signalling system that involves a snapshot of an account balance could be easily abused. This falls under the "morally dubious" but likely to be happen class of use case.

###### Edge-Case Exploits

A certain class of smart contract bug/exploit (likely) exists only if an attacker has an impractically large amount of ether. For example, a dapp with a rounding error in their bonded token price algorithm that results in unequal value/supply if 50x its balance is recursively bought and sold. Also "morally dubious" but likely possible.

### Questions/Extensions/Considerations

###### Standardize shares as ERC-20 tokens? 
Sure, why not.

###### Generalize contracts to support any ERC-20 asset? 
This would likely require separate pools for each asset to prevent slippage during price conversions. But there may be demand for a DAI or other stable coin version. The Uniswap model of a permissionless factory seems best in this scenario (they got a lot of things right).

###### Store dormant liquidity in some external interest bearing protocol? 

In theory, Planck could keep its liquidity in something like Compound, the Uniswap ETH/WETH pool, or any other protocol that does not restrict withdrawal timing. It could be removed/re-added in the same tx as a Planck loan. While this would add an additional source of revenue for liquidity providers, it would add gas costs for borrowers and increase overall complexity of the system. This type of functionality seems difficult to manage without messy DAO-type governance or some element of centralized decision making. 

###### What is a "Planck"?

A Planck unit is a system of measurement meant to describe some irreducible constant in a natural system. Basically, it's smallest something can be within the rules of a system. In this context, it's meant to reference the limits of time/sequence within the Ethereum protocol.

###### Why?

I kept getting annoyed when I had to turn off experimental bots to use their balances for something else. As far as I know, this general idea does not exist in the wild. I'm curious if it would actually work.
