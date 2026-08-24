# Field Assessment iOS

Offline-first field inspection app. Small domain, deep engineering.

The point of this project is not the inspection domain — it is answering one
question well: **what happens when the network disappears, the upload fails,
and the app is terminated halfway through synchronization?**

Every decision should be judged against that.

## Stack

- SwiftUI
- Core Data (persistence, chosen for transactional control)
- Swift Concurrency (async/await, actors)
- XCTest
- Fake backend in Python (FastAPI) with deliberate failure injection

## Architecture

```
Presentation  →  Domain  →  Data  →  Core Data / Network
```

Dependency rule: inner layers know nothing about outer layers.

- **Domain** holds plain Swift structs and use cases. It imports Foundation only.
  It must never import CoreData, SwiftUI, or URLSession.
- **Data** implements the repository protocols declared in Domain, and owns all
  Core Data and networking types.
- **Presentation** talks to use cases and repositories. It never touches
  infrastructure directly.

Domain models are separate types from Core Data entities. Mapping happens in Data.

## Hard rules

These are not preferences. Breaking them breaks the project.

1. **Uploads always go from file, never from `Data`.** Use
   `uploadTask(with:fromFile:)`. Background `URLSession` does not accept `Data`,
   and loading a 400 MB video into memory gets the app jetsammed.
2. **Store file names, not absolute paths.** The app container UUID changes
   between installs. Resolve the directory at runtime.
3. **`syncStatus` is derived, never stored.** It is computed from the Operation
   table. There is exactly one source of truth for sync state.
4. **Completing an assessment writes the status change and enqueues its
   operations in a single transaction.** Partial writes here mean work that
   silently never syncs.
5. **Entity IDs are UUIDs generated on the client**, at creation time, offline.
6. **Only `completed` assessments sync.** Drafts stay local. This is what removes
   the race between debounced auto-save and an in-flight upload.
7. **Sync is push-only.** Assessments are created on the device and only ever
   travel upward. Nothing is assigned or pulled from the server.

## What NOT to build yet

No premature abstraction. Every layer earns its existence by solving a problem
that already exists in the codebase.

Do not create, unless the current block explicitly calls for it:

- `SyncEngine`, `OperationQueue`, or any sync infrastructure before Block 2
- Chunked uploads — whole-file upload comes first, on purpose
- Chunking columns (`uploadId`, `totalChunks`, ...) sitting empty in the schema
- Generic `Repository<T>` abstractions
- A `GetAssessments` use case that only forwards to the repository
- Conflict resolution — the model is single-writer push-only by design

If a task seems to need one of these, say so and ask before building it.

## Conventions

- Use cases are named in domain language: `CreateAssessment`, not
  `InsertAssessment`.
- Use case entry point is `execute(...)`. Be consistent.
- Enums that get persisted use `String` raw values, never `Int` — reordering
  cases must not corrupt stored data.
- Never name a property `description`; it collides with
  `CustomStringConvertible`. Use `notes`.
- Validation that belongs to an entity lives on the entity, not in the use case.
- Validation returns the list of what is missing, not a `Bool`.

## Commits

- Never add a `Co-Authored-By` trailer. Commits carry one author.
- Explain why the change was made, not what the diff already shows.

## Testing

Failure paths are the product here, so they are not an afterthought.

Every sync behaviour needs a test that exercises the failure, not just the
happy path: timeout, 500, 400, lost response after commit, app killed
mid-flight, duplicate delivery.

Domain and use cases are tested against in-memory fakes. Repository tests use an
in-memory Core Data store.

## Reference

Read these when the task touches them — not by default.

- `docs/domain.md` — entities, invariants, completion rules
- `docs/sync-design.md` — outbox, operation lifecycle, retry, idempotency, recovery
- `docs/architecture.md` — layers, dependency rules, folder layout
- `docs/roadmap.md` — the four blocks and current scope
- `docs/decisions.md` — decision log with rationale
