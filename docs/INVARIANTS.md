---
description: Machine-checkable properties that must always hold — read before editing value-moving or mint logic.
scope: project
status: active
last_verified: 2026-07-28
read_when:
  - Before changing Token, AuctionHouse, Splitter, Descriptor, or draw libraries.
  - Auditing or adding verification.
do_not_read_when:
  - Editing pure tooling or docs with no on-chain behavior impact.
---

# Invariants

What must always be true in this system. When code and this file disagree, fix whichever is wrong in the same change.

All properties use **INV-{section}{n}** IDs (e.g. INV-A1, INV-C3). Primary enforcement lives in `test/invariants/InvariantI*.t.sol` (legacy I1–I17 filenames, mapped per row below); value-path side effects are pinned in `test/assurance/MutationSurvivorPoC.t.sol`. Catalog adopted from the 2026-07-27 external review (baseline f8b7138) and corrected to the Rev 10 splitter (90/5/5, commit 56ad408).

## Status legend

| Status | Meaning |
|--------|---------|
| ENFORCED | A check exists at the cited location |
| STRUCTURAL | Impossible by construction |
| PARTIAL | Enforced with a known gap |
| GAP | Not enforced yet |

## A — Assignment and ordering

| ID | Invariant | Status | Verification |
|----|-----------|--------|--------------|
| INV-A1 | Across reserved draw + all 9,800 daily draws, every design piece is assigned exactly once (bijection). | ENFORCED | `test/invariants/InvariantI1_Bijection.t.sol` (full walk) |
| INV-A2 | Design pieces 1 and 10,000 (indices 0, 9,999) never appear in the reserved 200. | ENFORCED | `InvariantI2_CornerstonesPublic.t.sol` (fuzz) |
| INV-A3 | Reserved draw yields exactly 100 artist + 100 team pieces, disjoint, in-domain. | ENFORCED | `InvariantI3_ReservedCountsExact.t.sol` (fuzz) |
| INV-A4 | Public token IDs mint strictly 1…9,800 in order, one per settlement; no other public mint path. | ENFORCED | `InvariantI5_SequentialMint.t.sol` + INV-A1 walk |
| INV-A5 | Exactly one live unsettled auction between genesis open and final settlement (except paused gap). | ENFORCED | `InvariantI6_OneLiveAuction.t.sol` (handler invariant) |
| INV-A6 | Genesis steps run only in order (seed → blob → artist tail → team tail → auction #1), each once, permissionless. | ENFORCED | `InvariantI17_GenesisOrdering.t.sol` |

## B — Randomness and reveal

| ID | Invariant | Status | Verification |
|----|-----------|--------|--------------|
| INV-B1 | After first VRF fulfillment, seed cannot change and reserved draw cannot re-run; settled daily draws cannot re-draw. | ENFORCED | `InvariantI4_SeedWriteOnce.t.sol` |
| INV-B2 | Piece for auction N+1 is not computable before settlement of auction N executes (`prevrandao` dependency; no leaking views). | PARTIAL | `InvariantI15_RevealOpacity.t.sol`. Accepted gap (review Finding 1, ruled 2026-07-28): the settlement caller sees one candidate per block and may defer — a scheduling bias only. The bijection (INV-A1) means every piece still auctions exactly once at public 24h auction; no piece, price or winner can be forced. Mitigation: a first-block settler keeper (ops, post-genesis) collapses the deferral window to zero. |
| INV-B3 | `publicPiece` blob is byte-identical to on-chain recomputation from seed; no external table submission path (STRUCTURAL: `materializeBlob` takes no table). | ENFORCED | `InvariantI16_BlobFidelity.t.sol` (bytes); submission arm STRUCTURAL |
| INV-B4 | Only the immutable VRF coordinator may fulfill; `reRequest` is permissionless only after the timeout and before seed set; request ExtraArgs are native-payment=false. | ENFORCED | `test/VRF.t.sol` (`test_INV_B4_*`, `testFuzz_INV_B4_*`) |
| INV-B5 | Only the MOST RECENT seed request may fulfill: a `reRequest` supersedes the prior request id (`activeSeedRequestId`), so a stale request delivered late cannot win the seed ahead of the operator's fresh request (Rev 12, audit M-01). Still write-once thereafter. | ENFORCED | `test/VRF.t.sol` `test_M01_OnlyMostRecentRequestCanFulfill`; `InvariantI4_SeedWriteOnce.t.sol` `test_I4_OnlyMostRecentRequestFulfills` |

## C — Conservation of value

| ID | Invariant | Status | Verification |
|----|-----------|--------|--------------|
| INV-C1 | Splitter never overpays: for every payee at all times `released[p] <= (totalReceived * shares(p)) / 100`; integer-division dust stays in the pot (≤1 wei per release round). | ENFORCED | `test/Splitter.t.sol` `testFuzz_EthAccounting_NeverOverpays`, `test_DoubleRelease_Reverts` |
| INV-C2 | Splitter funds are only ever transferred to the three payee addresses (company immutable; artist and designer rotatable ONLY via the payeeAdmin Safe behind the 48h public timelock, role-keyed accounting). Company `release` is permissionless; a rotatable payee (artist, designer) may release ONLY its own funds (`msg.sender == account`) — a lost key can never sign, so no third party can push a role's accrual to a lost or about-to-be-rotated address, before/during/after a rotation (Rev 12, audit H-01, H-02). No `release` can redirect. No payee may be the splitter itself (audit L-01), and no payee may be rotated onto the `payeeAdmin` — admin and payee roles stay separate across rotations, not only at construction (audit K-01). | STRUCTURAL/ENFORCED | company immutable; rotations timelocked with cross-payee + self-payee + admin guards; payee-only + self-payee + admin-separation tests `test_H02_*`, `test_L01_*`, `test_K01_*` in `test/Splitter.t.sol` |
| INV-C3 | An outbid always makes the previous bidder whole: refund of exactly their bid, via ETH or WETH fallback — never lost, never doubled. | ENFORCED | `_safeTransferETHWithFallback` in `src/AuctionHouse.sol`; INV-C6 + INV-D2 suites, `test/adversarial/`; balance-snapshot pins `test/assurance/MutationSurvivorPoC.t.sol` (MUT-003/005/006) |
| INV-C4 | A blocking payee cannot prevent the other payee from releasing their share (pull-payment isolation). | ENFORCED | `test/Splitter.t.sol` `test_INV_C4_BlockingPayee_CannotBlockTheOther` |
| INV-C5 | Refund-path reentrancy cannot successfully reenter `createBid` or settle; AH balance stays coherent (INV-C6). | ENFORCED | `test/adversarial/AdversarialBidders.t.sol` `test_INV_C5_ReentrancyProber_NoReentry` |
| INV-C6 | `AuctionHouse` ETH balance always equals current top bid after every transition. | ENFORCED | `InvariantI7_BalanceIntegrity.t.sol` (handler invariant) + INV-A1 walk |
| INV-C7 | Every settlement forwards exactly the hammer to the immutable splitter; 90/5/5 shares (company/artist/designer, Rev 10) never change. | ENFORCED | `InvariantI10_ProceedsRouting.t.sol (+ InvariantI10b_SplitterAccounting.t.sol)` (fuzz) + INV-A1 walk |

## D — Liveness

| ID | Invariant | Status | Verification |
|----|-----------|--------|--------------|
| INV-D1 | Once ended, settlement succeeds for any caller in the tested matrix (paused, hostile top bidder, no-bid burn); handler counts due-settle failures; a successful settle mints, pays the splitter and opens the next auction. | ENFORCED | `InvariantI8_SettleLiveness.t.sol` (handler + scenarios); side-effect pins `MutationSurvivorPoC.t.sol` (MUT-001/002/004) |
| INV-D2 | No refund recipient can cause outbid to revert or unbounded gas. | ENFORCED | `InvariantI9_RefundLiveness.t.sol` + `test/adversarial/` |

## E — Immutability and privilege

| ID | Invariant | Status | Verification |
|----|-----------|--------|--------------|
| INV-E1 | Privileged surface is exactly `{pause, scheduleUnpause}` on AuctionHouse; no `owner()` anywhere; privileged calls move no funds/mints/order. | ENFORCED | `InvariantI11_PrivilegeSurface.t.sol` + `DeployLib.verify` |
| INV-E2 | Token does not implement ERC-2981; zero secondary royalties (Rev 3). | ENFORCED | `test/Token.t.sol` (ERC-2981 negative in the interface test); `DeployLib.verify` |
| INV-E3 | Auction cadence constants, supply caps, splitter address, and VRF pins never change at runtime. | ENFORCED | `InvariantI14_CadenceImmutability.t.sol` (handler invariant) + `DeployLib.verify` |

## F — Rendering

| ID | Invariant | Status | Verification |
|----|-----------|--------|--------------|
| INV-F1 | `tokenURI` for all 10,000 pieces is deterministic and pixel-identical to frozen design renders. | ENFORCED | `InvariantI12_RenderFidelity.t.sol` (full pixel diff under `FOUNDRY_PROFILE=i12`) |
| INV-F2 | Descriptor constructor pins SSTORE2 art page hashes; tampered pages revert; semi-alpha encoding is Nouns-verbatim. | ENFORCED | `test/Descriptor.t.sol` `test_INV_F2_*` |
| INV-F3 | Late bids extend end time to `now + TIME_BUFFER` exactly; no over/under extension. | ENFORCED | `InvariantI13_AntiSnipe.t.sol` |

## G — Bid arithmetic

| ID | Invariant | Status | Verification |
|----|-----------|--------|--------------|
| INV-G1 | An accepted outbid satisfies `msg.value >= amount + max(amount * 2 / 100, 0.001 ether)`; one wei below reverts. Opening bid (no bidder yet) needs only `>= RESERVE_PRICE` (0). | ENFORCED | `test/BidIncrement.t.sol` boundary + dust tests |
| INV-G2 | A bid is only accepted for the live token ID before `endTime`; expired or wrong-ID bids revert. | ENFORCED | `createBid` requires in `src/AuctionHouse.sol`; `InvariantI13_AntiSnipe.t.sol`; `BidIncrement.t.sol` wrong-id / post-expiry fuzz |
| INV-G3 | A zero-bid auction burns the token at settlement; the piece assignment survives (feeds INV-A1). | ENFORCED | no-bid burn scenario in `InvariantI8_SettleLiveness.t.sol`; `test_Burn_OnlyAuctionHouse` in `test/Token.t.sol`; INV-A1 walk burn days |

## H — Pause state machine

| ID | Invariant | Status | Verification |
|----|-----------|--------|--------------|
| INV-H1 | Pause halts only creation of the *next* auction; in-flight bidding and settlement (`settleAuction`) always work while paused. | ENFORCED | `test/PauseSemantics.t.sol`, INV-D1 suite |
| INV-H2 | Unpause is reachable only via `scheduleUnpause` (guardian) + 48h maturity; execution is then permissionless. Re-pausing cancels any pending schedule. | ENFORCED | `unpause`/`pause` guards in `src/AuctionHouse.sol`; `test/PauseSemantics.t.sol` schedule/timelock/re-pause tests; `repauseCancel` handler action |
| INV-H3 | Unpause resumes the cadence: if the current auction settled while paused and the walk is not complete, the next auction opens in the unpause transaction. | ENFORCED | `test_Unpause_ResumesCadenceAfterPausedSettlement` |

## J — Deploy-time configuration

| ID | Invariant | Status | Verification |
|----|-----------|--------|--------------|
| INV-J1 | A production deploy cannot complete with: a zero address anywhere in the wiring; the deployer EOA as guardian, treasury, reserve or any payee; identical splitter payees; the payeeAdmin as an individual payee; the reserve as an individual payee; a zero descriptor; or (on mainnet) a non-canonical VRF coordinator. INTENTIONAL overlap: one team Safe fills treasury = payeeAdmin = reserve = guardian (single-Safe ruling 2026-07-20). | ENFORCED | `DeployLib.validate` (runtime assertion, incl. mainnet coordinator pin — review Finding 2) + `test/Deploy.t.sol` |
| INV-J2 | Post-deploy, the wiring graph is exactly token↔auctionHouse↔splitter with all §01 constants matching spec — including the token's immutable descriptor equal to the supplied config (review Finding 2) — or the script reverts. | ENFORCED | `DeployLib.verify` (runtime assertion, deploy-time twin of INV-E1/INV-E3) |
| INV-J3 | The AuctionHouse address prediction (`nonce + 1`) matches the deployed address, or deploy reverts — the Token's immutable minter is never wrong. | ENFORCED | `require` in `DeployLib.deploy` |

## Documented exceptions

- **Descriptor address(0) placeholder** — `Token.tokenURI` falls back to minimal data URI for test fixtures only. Production deploy **reverts** on zero descriptor (`DeployLib.validate`).
- **Pause gap** — While paused after settlement, no live auction exists until unpause (INV-A5 documents this as the only "at most one" exception).
- **Zero-bid burn** — A no-bid auction burns its token (Nouns-verbatim), so total *live* supply can be under 10,000; the assignment bijection (INV-A1) still holds because the piece was consumed.
- **Splitter dust** — Integer-division remainders (≤2 wei per round across the three payees) accumulate in the splitter rather than being distributed; accepted as part of the OZ PaymentSplitter pattern.

## Trust assumptions

- **Chainlink VRF v2.5** delivers unbiased random words within subscription limits; coordinator is the immutable mainnet address at deploy.
- **Ethereum `prevrandao`** is unpredictable before the settlement block exists; the settlement CALLER's one-candidate-per-block scheduling bias is accepted and bounded (see INV-B2).
- **Deployer** supplies correct treasuries, guardian Safe, and Descriptor page addresses at deploy; `DeployLib.verify` checks wiring post-deploy.
- **Art pipeline** — `DescriptorData.sol` hashes match deployed SSTORE2 page bytecode; encoding tool output is trusted until INV-F1 pixel diff passes.
- **Canonical WETH** — the hardcoded mainnet WETH (`0xC02a…6Cc2`) behaves per spec: `deposit` never reverts on value, `transfer` never reverts to a valid address. The refund-liveness invariants (INV-D2, INV-C3) depend on this.
- **Pause guardian** — the 3-of-5 Safe acts honestly within its narrow surface; a malicious guardian can at worst pause forever (no fund movement possible).
- **No malicious compiler/toolchain** — bytecode matches audited source.

## Maintenance

- Touch an enforcement site → re-check the affected rows in the same PR.
- Invariant files keep their legacy `InvariantI{n}_*` names; this catalog's per-row citations are the canonical map from INV-IDs to files. New tests reference the INV-ID in a comment.
- Status upgrades require the fixing test in the same change.
