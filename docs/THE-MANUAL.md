# CypherPunks — The Manual

*The operating manual for the CypherPunks system. Written to be read with
nothing but a node and a block explorer. The website is a convenience; this
manual and the contracts it describes are permanent. This document is
inscribed onchain at genesis (as an SSTORE2 data contract, the same mechanism
the art uses); its address is recorded in the genesis runbook and below.*

Manual inscription (SSTORE2 data contract): `<MANUAL_ADDRESS — filled at genesis>`
Inscription tx: `<MANUAL_TX — filled at genesis>`

---

## What this is

Ten thousand pixel identities ("CypherPunks"), fully onchain on Ethereum
mainnet. The art is not a link — it is generated inside the contracts. One
punk is auctioned every 24 hours until all 9,800 public pieces are gone; 200
were minted at genesis (100 an artists-allocation grants pool, 100 team).

There is no owner, no admin key that can move funds, mint, or change the
economics, and no upgrade path. What is written here is what the bytecode
does, forever.

## The contracts

| Contract | Address | Role |
|---|---|---|
| Token (ERC-721) | `<TOKEN>` | The 10,000 punks; VRF seed; daily mint |
| AuctionHouse | `<AUCTION_HOUSE>` | The daily auction, chained off settlement |
| Splitter | `<SPLITTER>` | Pull-payment 95 / 5 proceeds split |
| Descriptor | `<DESCRIPTOR>` | On-chain renderer (SSTORE2 + RLE art) |

(Addresses are filled at deploy; all four are verified on Etherscan at genesis.)

## Seeing a punk without the website

Call `tokenURI(uint256 tokenId)` on the **Token**. It returns a fully
self-contained `data:application/json;base64,…` URI — JSON metadata plus an
embedded SVG image, with **zero external references**. Decode the base64 and
you have the art and its traits. No server, no IPFS, no marketplace required.
`punkForToken(tokenId)` returns the design-piece number.

## The daily auction

- Each auction runs **24 hours**, its end time stamped at creation
  (`endTime = startTime + 24h`). The next auction is created inside the
  settlement of the current one — the cadence chains off settlement, not a
  clock.
- **Bid:** `createBid(uint256 tokenId)` payable, on the AuctionHouse, with the
  punk currently up for auction. An outbid must raise the price by
  `max(2%, 0.001 ETH)`; the opening bid need only meet the reserve (0). Your
  bid must be for the live `tokenId` and arrive before `endTime`.
- **Anti-snipe:** a bid inside the final **10 minutes** pushes `endTime` to
  10 minutes out. Contested pieces run until bidding stops.
- **Refunds** are automatic and immediate: when you are outbid, the prior bid
  is returned in the same transaction (ETH, or WETH if the recipient rejects
  ETH).
- **Settle:** `settleCurrentAndCreateNewAuction()` is **permissionless** —
  anyone can call it once `endTime` has passed. It transfers the punk to the
  winner, routes the proceeds to the Splitter, and opens the next auction. If
  a day drew **no bids**, that punk is burned (the design piece is still
  spent — coverage holds).
- **The end:** after the 9,800th settlement no new auction is created and the
  walk is complete (`AuctionWalkComplete`).

To keep the daily cadence honest, a keeper should call
`settleCurrentAndCreateNewAuction()` promptly at `endTime`; it is otherwise
open to anyone.

## Where the money goes

Proceeds go to the **Splitter**, split **95% team / 5% artist**, forever.
It is pull-payment: call `release(address payee)` (permissionless — funds only
ever go to the fixed payee) to withdraw the owed share. The same split applies
to anything the Splitter ever receives.

## What can and cannot change

**Cannot change, ever:** the 95/5 split; the team payee address; the total
supply; the auction parameters (duration, buffer, increment); the art; the
renderer. There is no owner and no setter for any of it.

**The one moving part — the artist *address*:** the 5% artist payee address
can be rotated by an immutable `payeeAdmin` Safe, but only after a **48-hour
timelock** (`proposeArtistUpdate` → wait 48h → `executeArtistUpdate`, which is
permissionless once matured; `cancelArtistUpdate` aborts). This exists only so
a lost artist key can be recovered; the *share* stays 5% and accrued-but-
unclaimed funds follow the role to the new address. The team payee has no
such path — it is a Safe and rotates its own signers.

**Pause:** a 3-of-5 guardian Safe can pause the creation of the *next* auction
and schedule an unpause behind a 48-hour timelock. It **cannot** touch an
in-flight auction, settlement, refunds, or any funds. Worst case: future
auctions are delayed, nothing is lost. Settlement remains callable while paused.

## Verifying genesis

The daily order and the reserved 200 were drawn from a single Chainlink VRF
seed, written once at genesis and then public. Anyone can reproduce the
reserved draw deterministically from that seed (see `ReservedDraw`) and confirm
no human chose which pieces went where. Design pieces #1 and #10,000
(cornerstones) can never be in the reserved set. The daily piece for auction
N+1 becomes knowable only inside the settlement of auction N.

## Verifying rarity

Rarity ranks are OpenRarity, recomputable from the frozen trait table by anyone
— they are not authoritative onchain state, just a derived convenience.

## Appendix — raw calls (no ABI, no explorer)

Everything above is doable with nothing but JSON-RPC. A function call is
`data = selector ++ arguments`, each argument ABI-encoded (left-padded to 32
bytes). The selectors below are the first 4 bytes of `keccak256` of the
signature — recompute them yourself if you don't trust this table.

| Action | Contract | Signature | Selector |
|---|---|---|---|
| Read current auction | AuctionHouse | `auction()` | `0x7d9f6db5` |
| Bid (send ETH as value) | AuctionHouse | `createBid(uint256)` | `0x659dd2b4` |
| Settle + open next | AuctionHouse | `settleCurrentAndCreateNewAuction()` | `0xf25efffc` |
| Auctions paused? | AuctionHouse | `paused()` | `0x5c975abb` |
| See a punk | Token | `tokenURI(uint256)` | `0xc87b56dd` |
| Design piece for token | Token | `punkForToken(uint256)` | `0x5b6879c3` |
| Owed to a payee | Splitter | `releasable(address)` | `0xa3f8eace` |
| Withdraw payee funds | Splitter | `release(address)` | `0x19165587` |

**Find what's on auction right now** — `eth_call` the AuctionHouse with data
`0x7d9f6db5`. The return is seven 32-byte words, in order: `tokenId`,
`pieceId`, `amount` (current high bid, wei), `startTime`, `endTime` (unix),
`bidder`, `settled`.

```
curl -s $RPC -X POST -H 'Content-Type: application/json' -d '{
  "jsonrpc":"2.0","id":1,"method":"eth_call",
  "params":[{"to":"<AUCTION_HOUSE>","data":"0x7d9f6db5"},"latest"]}'
```

**Bid** — send a transaction to the AuctionHouse with your bid as `value` and
data `0x659dd2b4` + the live `tokenId` left-padded to 32 bytes. Example for
tokenId 201: `0x659dd2b4` + `00…00c9`. Any wallet that lets you set raw
calldata can do this; with foundry it is one line:

```
cast send <AUCTION_HOUSE> "createBid(uint256)" 201 --value 1.5ether
```

**Settle** (anyone, once `endTime` has passed) — send data `0xf25efffc`, no
value. **Withdraw** (payees) — send data `0x19165587` + payee address padded
to 32 bytes; funds only ever move to the fixed payee, whoever calls.

---

*If a future reader finds a discrepancy between this manual and the deployed
bytecode, the bytecode wins. This document describes it; it does not govern it.*
