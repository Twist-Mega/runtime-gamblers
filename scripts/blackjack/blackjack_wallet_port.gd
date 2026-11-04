@abstract
class_name BlackjackWalletPort
extends RefCounted
## Implement this interface around the game's wallet; no wallet is owned here.

## Return the current nonnegative balance in integer money units.
@abstract
func get_balance() -> int

## Atomically apply a signed delta, or return false without changing the balance.
## Repeating a successful ID with the same delta must return true without applying
## it again. Reusing an ID with a different delta must return false.
## Reject deductions that exceed the balance and credits that would overflow it.
## Zero deltas are valid transactions. Calls must be synchronous.
@abstract
func apply_transaction(transaction_id: String, delta: int) -> bool
