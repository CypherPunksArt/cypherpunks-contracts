# CypherPunks Contracts

CypherPunks create art through code.

10,000 fully onchain punks. One auctioned every day, no reserve, until 2053.
No owner, no admin keys, no upgrades, zero royalties. The art, the auction,
the split, the mailing list, the user manual, and the auction interface itself
all live in Ethereum state.

The machine: https://cypherpunks.art
The launch, in long form: https://hashd.art/article/running-cypherpunks

## Deployed (Ethereum mainnet, genesis 2026-07-30)

| Contract | Address |
|---|---|
| Token (CypherPunks, PUNK) | [`0xA38ab198BE78d7Adf45652c522Cc6B4b8010520a`](https://etherscan.io/address/0xA38ab198BE78d7Adf45652c522Cc6B4b8010520a) |
| AuctionHouse | [`0x6f99cb3d3A3c10bDAA52204509f3d85F4697f1B8`](https://etherscan.io/address/0x6f99cb3d3A3c10bDAA52204509f3d85F4697f1B8) |
| Splitter | [`0x5562dcEb25e84a9EA4c244EC02A74C8c14f8B9e1`](https://etherscan.io/address/0x5562dcEb25e84a9EA4c244EC02A74C8c14f8B9e1) |
| Descriptor (the art) | [`0xF5303966F5FaD1d395ec96458dbb26876953F268`](https://etherscan.io/address/0xF5303966F5FaD1d395ec96458dbb26876953F268) |
| MailingList | [`0x5a9222764095d1D2400C4D5D3070bF907FaF6102`](https://etherscan.io/address/0x5a9222764095d1D2400C4D5D3070bF907FaF6102) |
| PFP Registry | [`0xcb3bA744322f9870F03331e0c25224CA775b1565`](https://etherscan.io/address/0xcb3bA744322f9870F03331e0c25224CA775b1565) |
| Manual | [`0xef499B5559E520B5144d08b9142dD8614D824A94`](https://etherscan.io/address/0xef499B5559E520B5144d08b9142dD8614D824A94) |
| AuctionTerminal (the auction UI, deployed 2026-08-09) | [`0x2932dd40C3f3f00A21ead842E5621c61ad69575f`](https://etherscan.io/address/0x2932dd40C3f3f00A21ead842E5621c61ad69575f) |

All source is verified (exact match): the genesis contracts on Etherscan, the
AuctionTerminal on [Sourcify](https://sourcify.dev/server/v2/contract/1/0x2932dd40C3f3f00A21ead842E5621c61ad69575f). The genesis seed was drawn
by Chainlink VRF; the token-to-punk order is a fixed bijection that did not
exist until the seed landed, and cannot be changed now that it has.

## Verify a punk yourself

Any Ethereum node can draw any punk. No IPFS, no image server, no API:

```bash
cast call 0xA38ab198BE78d7Adf45652c522Cc6B4b8010520a \
  "tokenURI(uint256)(string)" 1 --rpc-url https://ethereum-rpc.publicnode.com
```

The result is a base64 data URI containing the metadata and the SVG, rendered
by the Descriptor from bytes pinned at construction — the Descriptor's
constructor hash-checks every art page, so it could not have been deployed
with wrong bytes.

## The auction, without a website

The AuctionTerminal stores a complete HTML interface to the daily auction
onchain (24,506 bytes, written once, immutable, no owner). It reads the live
auction from any Ethereum RPC, draws the punk through `tokenURI`, and shows the
exact transaction fields to bid or settle from any wallet. If every website is
gone, the interface is still in the same place as the auction.

```bash
cast call 0x2932dd40C3f3f00A21ead842E5621c61ad69575f "ui()(string)" --json \
  --rpc-url https://ethereum-rpc.publicnode.com | jq -r '.[0]' > terminal.html
```

Open `terminal.html` in a browser. https://cypherpunks.art/terminal serves the
same bytes, read from the contract on each request.

## Build and test

Requires [Foundry](https://getfoundry.sh).

```bash
forge install foundry-rs/forge-std OpenZeppelin/openzeppelin-contracts
forge test
```

184 tests: unit, fuzz, invariant, and a hostile-handler suite ported from the
external reviews.

## What's in here

- `src/` — the contracts as deployed, byte-for-byte
- `test/` — the full suite, including auditor mutation PoCs
- `script/` — deploy scripts that reproduce genesis
- `docs/INVARIANTS.md` — the invariant catalog, including the accepted
  findings and their bounds
- `script/terminal.html` — the auction terminal page; `script/DeployTerminal.s.sol`
  writes the terminal's own address into its footer and deploys it, so the page
  stored at `0x2932dd40C3f3f00A21ead842E5621c61ad69575f` is this file with that
  one substitution
- `script/manual.txt` — the user manual inscribed onchain, byte-identical to
  the 2,027 bytes stored at `0xef499B5559E520B5144d08b9142dD8614D824A94`
- `docs/THE-MANUAL.md` — the longer companion manual (not the inscription; it
  carries errata for the two places the inscription is incomplete)
- `docs/art/` — the frozen art artifacts and their fingerprints
- `reference/` — vendored upstream sources (Nouns, OpenZeppelin, Chainlink),
  provenance in `VENDORED_FROM.txt`

## Security

Seven independent review passes (multi-model adversarial audits plus an
external developer review) before genesis; every finding fixed or disclosed
in `docs/INVARIANTS.md`. The contracts are immutable: there is nothing to
upgrade, pause beyond the bounded guardian, or administer. Found something
anyway? kenny@cypherpunks.art.

## License

- **Code: GPL-3.0** ([LICENSE](LICENSE)) — inherited from Nouns, kept gladly.
  Fork the machine; your fork stays open too.
- **Art: CC0 1.0** ([ART-LICENSE](ART-LICENSE)) — all 10,000 punks are
  dedicated to the public domain. Use them for anything, no permission
  needed, no attribution required.

The code is GPL. The art is CC0. The provenance is forever.
