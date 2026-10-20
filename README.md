# Messenger (MAIL)

Messenger is a fixed supply ERC-20. Its constructor mints **1,000,000,000 MAIL**
with **18 decimals** to the immediate deployer. Every transfer delivers the exact
requested amount.

## Contract and deployment parameters

| Parameter | Value |
| --- | --- |
| Solidity contract / artifact | `src/Messenger.sol:Messenger` |
| Name | `Messenger` |
| Symbol | `MAIL` |
| Decimals | `18` |
| Supply in whole tokens | `1,000,000,000` |
| Supply in smallest units | `1000000000000000000000000000` (`10^27`) |
| Named supply constant | `INITIAL_SUPPLY` |
| Constructor arguments | None (`[]`) |
| Constructor value | `0` |
| Initial recipient | `msg.sender`, the immediate deploying account or factory |
| Launch chain specified by the assignment | Robinhood Chain, chain ID `4663` |
| Solidity compiler | `0.8.26` |
| EVM target | `paris` |
| Optimizer | Enabled, `200` runs |
| Metadata bytecode hash | `none` |

The constructor makes no external calls and requires no other contracts to exist.
There are no linked libraries, initializer calls, or application contracts. Use
the creation bytecode in `out/Messenger.sol/Messenger.json` without constructor
arguments. Deploy this contract directly, including through the launch factory's
CREATE2 operation; it is not a proxy implementation.

The factory receives the full supply when it creates Messenger. The account
calling the factory receives none during construction. Under the assignment's
launch policy, the factory subsequently distributes 10% to the swarm
distributor, 70% to the pool, and 20% to the designated remainder recipient.
Those allocations and the pool configuration are the external launch system's
responsibility; the token itself only implements exact ERC-20 transfers.
The separate manifest step supplies the actual launch addresses and writes
`launch.json`.

## Behavior and assumptions

- Minting happens exactly once, in construction. The deployed contract has no
  external mint or burn function, so its total supply stays fixed.
- No owner, administrator, pause, blacklist, transfer tax, rebasing, upgrade, or
  confiscation mechanism exists.
- `transfer`, `approve`, and `transferFrom` return `true` on success and revert
  with OpenZeppelin's ERC-6093 custom errors on invalid actions.
- Zero-value transfers between nonzero accounts are allowed and emit `Transfer`.
  Self-transfers preserve balances. Transfers to the zero address and approvals
  to a zero spender revert.
- A finite allowance is consumed by `transferFrom`; the maximum `uint256`
  allowance is treated as unlimited and remains unchanged. `approve` replaces an
  allowance. Failed operations preserve balances and allowances.
- Explicit approvals emit `Approval`. Following OpenZeppelin v5 behavior,
  spending an allowance emits `Transfer` without an additional `Approval`.
  Integrations should query `allowance` when they need the remaining amount.
- The contract performs no recipient callbacks, reads no oracle, and uses no
  block-number, timestamp, sequencer, bridge, or chain-specific precompile logic.
  The conservative Paris target avoids requiring newer EVM instructions.
- Ordinary native-currency payments revert. There is no recovery function for
  tokens sent to this contract or native currency forcibly delivered to it.

## Build and test

Foundry and Solidity `0.8.26` must be available. All Solidity dependencies are
vendored as ordinary files under `lib/`, including their licenses. No dependency
download, RPC, environment-based test configuration, FFI, or filesystem permission
is needed. See [DEPENDENCIES.md](DEPENDENCIES.md) for pinned versions and hashes.

```sh
forge build
FOUNDRY_FUZZ_SEED=0xc47c8c7d2e657ac7df29b404ef5fdc0ae71dca75914682ea58839936e69a09c8 forge test
forge fmt --check
```

The suite covers constructor supply and mint events; exact transfers; approvals,
revocation and unlimited allowances; zero amounts and self-transfers; insufficient
balances and allowances; rollback on failed transfers; forbidden administrative
entrypoints; CREATE2 factory deployment; exact launch allocation and claim flows;
and token transfers into and out of a simulated pool manager.

Four fuzz tests exercise arbitrary recipients, transfer amounts, allowance
consumption, and insufficient-balance/allowance failures (512 runs each).
A stateful invariant executes transfer/approve/transferFrom sequences across four
actors (128 runs, depth 64), checking fixed supply, balance conservation, and
allowance accounting.

The pool-flow test models the token side of settlement, not a live Uniswap v4
pool. The supplied protected tests also depend on the network's launch harness,
manifest configuration, and Uniswap contracts; those are evaluated separately
by the verifier. They are not part of this standalone test suite.

## After launch and operational responsibilities

No owner configuration, activation, maintenance transaction, or external service
is required for the token. The launch operator is responsible for deploying the
reviewed bytecode on the assigned chain, applying the launch allocations, checking
the initial supply and balances, and verifying source and compiler settings on
the chain's explorer.

Holders control their tokens and spending approvals. Integrations should request
only the allowance they need. When replacing an existing nonzero allowance,
holders should revoke it first and wait for confirmation to reduce the standard
ERC-20 allowance-change race. Administrators cannot recover mistaken transfers,
revoke a holder's approvals, or restore lost keys.

Local testing is not an independent security audit. Independent adversarial review
and the network's full launch/AMM checks remain release responsibilities.
