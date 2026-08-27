# Field Assessment iOS

Offline-first field inspection app. Small domain, deep engineering.

The point of this project is not the inspection domain — it is answering one
question well: **what happens when the network disappears, the upload fails,
and the app is terminated halfway through synchronization?**

Every decision should be judged against that.

## The rule above the rules

The immutable goal is the finished software: clean, testable, reliable, easy to
understand, easy to maintain, and working. Everything else in this file and in
`docs/` is the current best hypothesis about how to get there — direction, not
definition.

When a documented rule works against that goal, say so. Raise the point every
time; the call is the owner's, never the assistant's. Silently following a rule
into a worse product is the one failure that is not acceptable.

Two kinds of rule, treated differently:

- **Constraints imposed by reality** are not up for negotiation. Background
  `URLSession` does not accept `Data`. The app container UUID changes between
  installs. Arguing with these does not improve the design, it breaks the app.
- **Design choices** are open. Push-only sync, drafts staying local, the field
  list in `docs/domain.md`, the order of the blocks — all decided with the
  information available at the time. If the code shows one of them costing more
  than it returns, that is worth saying out loud.

Changing a rule means changing the document that states it, in the same commit,
with the reason. Documentation describing a system that no longer exists is
worse than no documentation, and "easy to understand and maintain" is the first
thing lost when the two drift apart. `docs/decisions.md` is the log for why.

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

## Explaining things

Explanations are part of the work, not a wrapper around it. A design that
cannot be explained plainly is usually not understood yet.

- Walk the concrete sequence. "The photo is copied to a temp file, then moved,
  then the row is written" beats "the operation is not atomic across the two
  stores".
- Name the thing that breaks and what the person loses. Not "an inconsistent
  state", but "the photo is on disk and counts as lost".
- No jargon where a plain word works, and no rhetorical flourish. If a term is
  unavoidable, define it once in the sentence that introduces it.
- State the cost and what the solution does *not* solve, in the same breath as
  the solution.
- Short. The explanation ends when the point is made.

## Commits and pull requests

- Explain why the change was made, not what the diff already shows.
- **No tool attribution anywhere.** No `Co-Authored-By` trailer, no "generated
  with" line, no bot footer, no emoji signature — not in commit messages, not
  in pull request titles or bodies, not in issues or code comments. The work
  carries one author, and how it was written is not part of the record.
- This applies to text written into the repository and to text pushed to
  GitHub. If a default template adds such a line, remove it before sending.

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
