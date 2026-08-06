# CypherPunks — The Manual

*The operating manual for the CypherPunks system. Written to be read with
nothing but a node and a block explorer. The website is a convenience; the
contracts this manual describes are permanent.*

**This file is not the onchain inscription.** The inscribed manual is the
shorter `script/manual.txt`, stored as an SSTORE2 data contract at
`0xef499B5559E520B5144d08b9142dD8614D824A94` and readable with `read()`. Those
2,027 bytes are byte-identical to `script/manual.txt` and cannot be changed.
This document is the longer companion, it can be corrected, and where the two
differ the bytecode wins over both. See "Errata to the onchain manual" below
for the two places the inscription is incomplete.

---

## What this is

Ten thousand pixel identities ("CypherPunks"), fully onchain on Ethereum
mainnet. The art is not a link — it is generated inside the contracts. One
punk is auctioned every 24 hours until all 9,800 public pieces are gone; 200
were minted at genesis (100 an artists-allocation grants pool, 100 team).

There is no owner, no upgrade path, and no key that can mint, change the
split, or withdraw the proceeds. Two narrow admin powers do exist and are
described in full below: a guardian Safe can pause the creation of the *next*
auction, and a `payeeAdmin` Safe can rotate the artist and designer payee
addresses behind a 48-hour timelock. Neither can touch a live auction, a bid,
a refund, or the size of anyone's share.

## The contracts

| Contract | Address | Role |
|---|---|---|
| Token (ERC-721) | `0xA38ab198BE78d7Adf45652c522Cc6B4b8010520a` | The 10,000 punks; VRF seed; daily mint |
| AuctionHouse | `0x6f99cb3d3A3c10bDAA52204509f3d85F4697f1B8` | The daily auction, chained off settlement |
| Splitter | `0x5562dcEb25e84a9EA4c244EC02A74C8c14f8B9e1` | Pull-payment 90 / 5 / 5 proceeds split |
| Descriptor | `0xF5303966F5FaD1D395ec96458DBb26876953f268` | On-chain renderer (SSTORE2 + RLE art) |
| Manual | `0xef499B5559E520B5144d08b9142dD8614D824A94` | The inscribed manual (`read()`) |

(All four core contracts are verified on Etherscan.)

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
  spent — coverage holds). **While the auction house is paused this function
  reverts**; settlement is then done with `settleAuction()`, which settles the
  finished auction without opening the next one. Check `paused()` first.
- **The end:** after the 9,800th settlement no new auction is created and the
  walk is complete (`AuctionWalkComplete`).

To keep the daily cadence honest, a keeper should call
`settleCurrentAndCreateNewAuction()` promptly at `endTime`; it is otherwise
open to anyone.

## Where the money goes

Proceeds go to the **Splitter**, split **90% company / 5% artist / 5%
designer**, forever. The same split applies to anything the Splitter ever
receives.

It is pull-payment, via `release(address payee)`. Who may call it depends on
the role: the **company** share is permissionless, anyone may push it to the
fixed company address. The **artist** and **designer** shares are
self-release only — the contract requires `msg.sender == account`, so a third
party or keeper calling on their behalf reverts and loses gas. Funds are never
at risk either way; they only ever move to the payee that earned them.

## What can and cannot change

**Cannot change, ever:** the 90/5/5 split; the company payee address; the
total supply; the auction parameters (duration, buffer, increment); the art;
the renderer. There is no owner and no setter for any of it.

**The moving parts — the artist and designer *addresses*:** both 5% payee
addresses can be rotated by an immutable `payeeAdmin` Safe, and only after a
**48-hour timelock** (`proposeArtistUpdate` → wait 48h → `executeArtistUpdate`,
which is permissionless once matured; `cancelArtistUpdate` aborts; the same
three exist for the designer). This exists only so a lost key can be
recovered; the *shares* stay 5% each and accrued-but-unclaimed funds follow
the role to the new address. The company payee has no such path — it is a Safe
and rotates its own signers.

**Pause:** a 3-of-5 guardian Safe can pause the creation of the *next* auction
and schedule an unpause behind a 48-hour timelock. It **cannot** touch an
in-flight auction, settlement, refunds, or any funds. Worst case: future
auctions are delayed, nothing is lost. Settlement remains callable while
paused, through `settleAuction()`.

## Verifying genesis

The daily order and the reserved 200 were drawn from a single Chainlink VRF
seed, written once at genesis and then public. Anyone can reproduce the
reserved draw deterministically from that seed (see `ReservedDraw`) and confirm
no human chose which pieces went where. Design pieces #1 and #10,000
(cornerstones) can never be in the reserved set. The daily piece for auction
N+1 becomes knowable only inside the settlement of auction N.

**A known limit on that draw.** The next piece is selected from the settling
block's `prevrandao`, and settlement is permissionless with no deadline. A
block proposer or builder able to include, delay, or withhold the settlement
transaction can therefore influence *which* remaining piece comes up next. It
is a sequencing advantage and nothing more: it cannot mint that piece to
anyone, change the current winner, skip the 24-hour public auction, duplicate
a piece, or redirect a single wei. Every piece still has to clear the same
open auction. This is `INV-B2` in `docs/INVARIANTS.md`, accepted at design
time and stated here so no bidder learns it from someone else.

## Verifying rarity

Rarity ranks are OpenRarity, recomputable from the frozen trait table by anyone
— they are not authoritative onchain state, just a derived convenience.

## Errata to the onchain manual

The inscription at `0xef499B5559E520B5144d08b9142dD8614D824A94` is permanent
and cannot be corrected, so its two omissions are recorded here. Neither costs
anyone their principal; both can cost gas or cause a refund to look missing.

1. **Refunds are ETH, or canonical WETH.** The inscription says an outbid
   returns your ETH. The AuctionHouse first tries a 30,000-gas ETH transfer;
   if that fails, it wraps the exact amount into canonical WETH
   (`0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2`) and sends that instead. The
   amount is always exact and is never retained by the auction house. If you
   bid from a contract, make sure it can transfer an ERC-20, or your refund
   will sit at your own address with no way to move it.
2. **Settlement while paused uses a different function.** The inscription
   gives only `settleCurrentAndCreateNewAuction()`, which reverts while the
   auction house is paused. Read `paused()` first and call `settleAuction()`
   when it is true.

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
| Settle while paused | AuctionHouse | `settleAuction()` | `0xa4d0a17e` |
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
  "params":[{"to":"0x6f99cb3d3A3c10bDAA52204509f3d85F4697f1B8","data":"0x7d9f6db5"},"latest"]}'
```

**Bid** — send a transaction to the AuctionHouse with your bid as `value` and
data `0x659dd2b4` + the live `tokenId` left-padded to 32 bytes. Example for
tokenId 201: `0x659dd2b4` + `00…00c9`. Any wallet that lets you set raw
calldata can do this; with foundry it is one line:

```
cast send 0x6f99cb3d3A3c10bDAA52204509f3d85F4697f1B8 "createBid(uint256)" 201 --value 1.5ether
```

**Settle** (anyone, once `endTime` has passed) — send data `0xf25efffc`, no
value; if `paused()` returns true, send `0xa4d0a17e` instead. **Withdraw** —
send data `0x19165587` + the payee address padded to 32 bytes. Anyone may do
this for the company share; the artist and designer must send it themselves,
from the payee address, or it reverts.

---

*If a future reader finds a discrepancy between this manual and the deployed
bytecode, the bytecode wins. This document describes it; it does not govern it.*
