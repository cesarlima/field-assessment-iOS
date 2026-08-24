# Architecture

## Layers

```
Presentation  →  Domain  ←  Data
```

Domain sits in the middle and depends on nothing. Data depends on Domain because
it implements protocols Domain declares. This is dependency inversion: the arrow
points inward from both sides.

### Domain

Plain Swift structs, use cases, and repository protocols. Imports Foundation and
nothing else.

If Domain ever imports `CoreData`, `SwiftUI`, or `URLSession`, the boundary has
been broken.

### Data

Core Data model, `NSManagedObject` subclasses, the network client, the sync
engine, filesystem access. Implements the repository protocols.

Managed objects never leave this layer. Mapping to and from domain structs
happens at the repository boundary.

### Presentation

SwiftUI views and view models. Calls use cases and repositories. Never touches
Core Data or URLSession directly.

## Why separate domain models from Core Data entities

It costs mapping code, so it needs a reason. Three:

- `NSManagedObject` is not `Sendable` and is bound to its context's thread. Swift
  Concurrency and managed objects crossing actor boundaries is a known source of
  crashes.
- Domain rules stay testable without spinning up a persistent store.
- The persistence choice stays replaceable. Core Data was chosen for
  transactional control; that decision should not leak into every file.

## Folder layout

```
FieldAssessment/
  Domain/
    Entities/
      Assessment.swift
      AssessmentStatus.swift
      Evidence.swift
      EvidenceType.swift
      Operation.swift
    UseCases/
      CreateAssessment.swift
      UpdateAssessment.swift
      AddEvidence.swift
      CompleteAssessment.swift
    Repositories/
      AssessmentRepository.swift
      OperationRepository.swift
  Data/
    Persistence/
      Model.xcdatamodeld
      CoreDataAssessmentRepository.swift
      Mappers/
    Network/
    Files/
  Presentation/
    AssessmentList/
    AssessmentDetail/
    Debug/
FieldAssessmentTests/
```

`Operation.swift` and `OperationRepository.swift` do not exist until Block 2.
`Debug/` is the queue inspection screen — see below.

## Concurrency

Repositories are `async` and `Sendable`. The sync engine is an actor: it must
never process the same operation twice concurrently.

Core Data work happens on a background context. Only mapped domain structs cross
back out.

## The debug screen

A plain internal screen listing the operation queue: type, state, attempt count,
next attempt time, last error.

It is cheap, it is what a real field app needs for support, and it demonstrates
the sync design more convincingly in an interview than any explanation.

## Testing strategy

- Domain and use cases: in-memory fakes, no persistence.
- Repositories: in-memory Core Data store.
- Sync engine: fake network client with scripted responses, including delays,
  timeouts, and commit-then-fail.

An in-app network toggle makes offline behaviour reproducible by hand.

## The fake backend

Python, FastAPI, SQLite. It is a test instrument, not a product — its job is to
fail on command.

Endpoints:

```
POST  /assessments                  accepts a client-generated id
POST  /assessments/{id}/evidences   multipart file upload
GET   /assessments                  inspection, for debugging
POST  /_control/failure             set the next failure mode
```

Failure modes it must support, from Block 1:

| Mode | Simulates |
|---|---|
| `delay` | slow network |
| `timeout` | request that never answers |
| `error_400` | permanent client error, must not be retried |
| `error_500` | transient server error, must be retried |
| `commit_then_fail` | server stores the record, then the response is lost |

`commit_then_fail` is the important one. It is the only way to exercise
idempotency honestly, and it is the scenario the whole design exists for.

Every write endpoint reads an idempotency key from the request. The server keeps
a table of keys it has already handled together with the response it returned,
and replays that response instead of processing again. Without this the retry
logic cannot be verified at all.

## Non-goals

Stated explicitly so they read as decisions rather than omissions:

- No conflict resolution. The model is single-writer and push-only.
- No server-to-client sync of any kind. Assessments originate on the device.
- No back office, no assignment of work.
- No multi-user or role handling.
- No real backend. The fake server exists to fail on demand.
