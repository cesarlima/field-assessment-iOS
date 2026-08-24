# Sync design

This is the core of the project. Everything else exists to support it.

## The problem with storing sync state on the entity

If "this assessment needs to upload" lives as an enum on the entity, it cannot
carry the information sync actually needs: how many attempts have happened, when
to try again, which error occurred, which key to send, and in what order.

Worse, it has no answer for the app dying with `syncStatus = syncing`. Did it
reach the server? Nobody knows.

So the intent is stored as its own row instead.

## The outbox

Three tables: Assessment, Evidence, Operation.

- Assessment and Evidence hold **what exists**.
- Operation holds **what is still owed**.

Like an email outbox: the message is one thing, the queued item waiting to be
sent is another. The message survives sending; the queued item does not.

```
id              UUID          also the idempotency key
type            OperationType submitAssessment | uploadEvidence
entityId        UUID          assessment or evidence
payload         String        JSON blob
state           String        pending | inFlight | done | failed
attemptCount    Int
nextAttemptAt   Date
lastError       String?
createdAt       Date
```

### Why payload is a JSON blob

Different operation types need different data. Dedicated columns would leave half
the table permanently null, and every new operation type would mean a Core Data
migration.

Type safety is kept in Swift with an enum carrying associated values, encoded on
write and decoded on read:

```swift
enum OperationPayload: Codable {
    case submitAssessment(location: String, inspector: String, notes: String?)
    case uploadEvidence(fileName: String, mediaType: EvidenceType)
}
```

Trade-off: you cannot query on anything inside the blob. Acceptable, because the
engine only ever queries on `state` and `nextAttemptAt`, which are real columns.
If a field ever needs to be queryable, promote it to a column then.

## Walkthrough

**1. Inspector creates an assessment** — `status = open`. No operations. Drafts
do not sync.

**2. Fills fields, captures two photos** — Evidence rows created, files written
to disk. Still no operations.

**3. Taps Complete** — in a single transaction:

```
Assessment  A1  status = completed

Operation   O1  submitAssessment  entityId=A1  pending
Operation   O2  uploadEvidence    entityId=E1  pending
Operation   O3  uploadEvidence    entityId=E2  pending
```

Atomic because a crash between the status change and the enqueue leaves a
completed assessment that will never sync, with nothing to indicate it.

**4. Engine picks the first** — marks `inFlight` before sending.

**5. Server returns 500** — back to `pending`, `attemptCount = 1`,
`nextAttemptAt = now + backoff`.

**6. Retry succeeds** — `state = done`.

**7. App killed mid-flight on O2** — the row is frozen at `inFlight`.

**8. Next launch** — every `inFlight` row goes back to `pending`. Without this,
O2 is stuck forever.

**9. O2 is resent** — the server may already have processed it before the
response was lost. Same idempotency key means the server returns the original
result instead of storing a second copy.

**10. Queue drains** — no pending operations for A1, so the UI shows synced.

## The engine loop

```
1. fetch operations where state == pending and nextAttemptAt <= now,
   ordered by createdAt
2. take the first
3. mark inFlight
4. send
5a. success                          → state = done
5b. permanent error (400, 401, 422)  → state = failed, stop
5c. transient error (500, timeout,
    no connectivity)                 → attemptCount += 1
                                       nextAttemptAt = now + backoff
                                       state = pending
6. repeat
```

Classifying the error is the whole point of step 5. Retrying a 400 forever is a
bug, not resilience.

## Backoff

```
delay = min(base * pow(2, attemptCount), ceiling) + jitter
```

Roughly 1s, 2s, 4s, 8s, up to a few minutes. Jitter is a small random value so
that many clients coming back online do not hit the server in lockstep.

After a maximum attempt count, the operation goes to `failed` and waits for an
explicit user retry rather than burning battery forever.

## Idempotency

The operation's own `id` is the key. One column, because there is exactly one
request per operation.

It is the operation's id and not the entity's, because one entity can produce
several operations over its lifetime. Keying by entity would make the server
reject the second, different operation as a duplicate — a silent bug.

Conceptually these are two different things that happen to share a value today:
`id` is local identity, the key is a network contract. They separate the moment
one operation becomes several requests, which is what chunked upload does.

The client-generated entity UUID is complementary, not the same mechanism: it
stops the same assessment becoming two server records.

The server must keep a record of keys it has seen along with the response it
gave, and replay that response rather than reprocessing.

## Recovery on launch

```
UPDATE operations SET state = 'pending' WHERE state = 'inFlight'
```

Anything left `inFlight` means the process died mid-send. Nobody is going to
finish it.

This is where idempotency earns its keep — the resend may be a duplicate, and
the server has to absorb that.

## Derived sync status

Never stored. Computed from the operations belonging to the assessment **and to
its evidences**:

```
any failed    → failed
any inFlight  → syncing
any pending   → pending
none          → synced
```

Order is precedence: a failure is what the user needs to see first.

An assessment that is still `open` has no operations at all, so it returns nil
rather than "synced" — a draft is not synchronized, it is simply not meant to
upload.

`done` rows are kept, not deleted. They do not affect the calculation and they
feed the debug screen: attempted four times, 500 on the first three, succeeded on
the fourth.

## Operation ordering

`uploadEvidence` cannot run before its assessment exists on the server. Simplest
correct approach: process in `createdAt` order and do not skip ahead past an
operation that has not completed.

## Media

Whole-file upload first — one operation, one file, one request. Deliberately
naive, so the failure mode is felt: connection drops at 80% of a 300 MB video and
the whole thing restarts, because `uploadTask` has no resume support.

Only then chunking, which is documented in `decisions.md` as designed but not
necessarily built.

## Background URLSession constraints

These shape the queue design and cannot be retrofitted:

- The upload must come from a file, never `Data`.
- The system owns the transfer, not the app. It continues while the app is
  suspended or terminated.
- Callbacks can arrive after the app has relaunched from scratch, into
  `handleEventsForBackgroundURLSession`.
- Therefore the mapping between `URLSessionTask` and Operation must be persisted,
  not held in memory.

## Failure scenarios to test

- offline the whole time
- connectivity returns
- connectivity drops mid-upload
- timeout
- HTTP 400, 401, 500
- server commits then the response is lost
- app terminated mid-flight, then relaunched
- duplicate delivery of the same operation
- several pending operations at once
- large file
- disk write failure
