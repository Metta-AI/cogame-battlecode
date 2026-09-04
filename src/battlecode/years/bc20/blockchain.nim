## The 2020 blockchain: the transaction pool, `Transaction.compareTo`, and the
## per-round mint of at most `NUMBER_OF_TRANSACTIONS_PER_BLOCK = 7`.
##
## Pure: no world state, so `world.nim` can import it. The world owns the pool
## and the minted chain; this module owns the record and the ORDER.
##
## `common/Transaction.java`:
##
##     if (other.cost != this.cost) return other.cost - this.cost;   // higher cost first
##     if (other.id   != this.id)   return other.id   - this.id;     // higher id first
##     return serializedMessage.compareTo(other.serializedMessage);  // lexicographically earlier first
##
## and the serialized message is the seven ints rendered with
## `Integer.toString` and joined by `_`.
##
## The engine drains a `PriorityQueue` with `poll()`; a full tie in all three
## keys is the one case a binary heap and a sorted extraction can disagree on,
## and it needs two transactions with the same cost, the same 32-bit random id
## and the same seven ints. A stable sort is used here so the order is total
## and deterministic (docs/RULES-BC20.md §Divergences).

import std/[algorithm, strutils]

const TransactionLength* = 7

type
  Transaction* = object
    cost*: int
    message*: array[TransactionLength, int]
    id*: int32
    serialized*: string
    team*: int          ## 0 = A, 1 = B; `transactionToTeam` in the engine

proc serializeMessage*(message: array[TransactionLength, int]): string =
  var parts: seq[string]
  for v in message:
    parts.add($int32(v))
  parts.join("_")

proc newTransaction*(cost: int, message: array[TransactionLength, int],
                     id: int32, team: int): Transaction =
  Transaction(cost: cost, message: message, id: id,
              serialized: serializeMessage(message), team: team)

proc compareTransactions*(a, b: Transaction): int =
  ## Sorts the pool into MINTING order: `a` before `b` when `a.compareTo(b) < 0`.
  if a.cost != b.cost:
    return b.cost - a.cost
  if a.id != b.id:
    return (if b.id > a.id: 1 else: -1)
  cmp(a.serialized, b.serialized)

proc mintBlock*(pool: var seq[Transaction], perBlock: int): seq[Transaction] =
  ## Drains up to `perBlock` transactions in comparator order. Everything that
  ## did not make the cut STAYS IN THE POOL and remains eligible for ever.
  if pool.len == 0:
    return @[]
  pool.sort(compareTransactions)
  let take = min(perBlock, pool.len)
  result = pool[0 ..< take]
  for _ in 0 ..< take:
    pool.delete(0)
