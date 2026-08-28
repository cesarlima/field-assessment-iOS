# Roadmap

Four blocks. Not fifteen milestones — the value is concentrated, and spreading it
thin produces four half-finished features instead of one complete story.

Build in problem-first order: implement the naive version, feel the failure, then
engineer the real solution. That sequence is what turns a copied pattern into a
decision you can defend.

## Where this is

Last updated 2026-08-28.

The domain layer is finished and merged. The app around it has not started:
there is a workspace and a Swift package, no app target, no Core Data stack, no
screen, no fake backend. Block 1 is the next thing.

Threads left open on purpose, each recorded where the reasoning lives:

- **Uniqueness constraint on the evidence id.** Decision 23. Two `CapturedFile`
  values built with the same id and different assessments would put a duplicate
  row back; no screen does that, and the constraint closes it durably. Lands
  with the repository in Block 1.
- **The two `catch` branches in `CreateAssessment`.** Decision 25. They absorb
  an id that is already taken. Whether they are needed at all is decided by how
  the draft screen writes, so the question is asked again in Block 1.
- **`CompleteAssessment` writes only the status.** Decision 21. Hard rule 4 asks
  for the status change and the operations in one transaction, and there are no
  operations yet. Closes in Block 2.
- **Orphan-file sweep at launch.** Decisions 15 and 19. Filing a capture moves
  the file before the row is written, so a crash in between leaves a file the
  name identifies and nothing points at. Needs the file store, so Block 3.
- **Editing what an attached piece of evidence says.** Block 3 below.
- **Dependency-rule check.** "After, if time allows" below.

## Block 0 — Domain

Done. Merged in pull request #1.

- Entities and the invariants that live on them: `Assessment`, `Evidence`, the
  status and requirement enums, and the errors they raise
- Ports the outer layers implement: `AssessmentRepository`, `EvidenceFileStore`
- Use cases: `CreateAssessment`, `UpdateAssessment`, `AddEvidence`,
  `CompleteAssessment`
- Compare-and-set on every write, through one shared `commit` helper
- 54 tests against in-memory fakes, run in CI on every pull request

This was not one of the four blocks. The blocks describe the app being built;
this is the layer all of them sit on, and it came first because the rules had to
be settled before anything could store them. It is recorded here so the roadmap
matches the repository rather than the plan.

## Block 1 — Vertical slice

Goal: something that works end to end, however thin.

- Core Data stack
- Create, edit, list assessments locally
- Debounced auto-save, with flush when a field is left and when the app
  backgrounds
- Fake backend with failure injection and an in-app network toggle
- One operation uploading

No sync engine. No queue. One operation, sent directly, so the next block has a
concrete thing to generalise from.

## Block 2 — Sync core

The highest-value block. Most interview questions live here.

- Operation table (outbox)
- Sync engine as an actor
- `CompleteAssessment` writing status and operations in one transaction
- Error classification: transient vs permanent
- Retry with exponential backoff and jitter
- Idempotency, end to end, including server-side deduplication
- Recovery on launch for orphaned `inFlight` operations
- Derived sync status in the UI
- Debug screen showing the queue

Failure tests are written alongside, not after.

## Block 3 — Media

- AVFoundation capture: photo, video, audio
- Files on disk, metadata in Core Data, file names only
- `uploadEvidence` as an independent operation
- Whole-file upload from file, never from `Data`
- Editing what an attached piece of evidence says. Today the only way to reach
  `Evidence.notes` is at capture time: repeating a capture to change its note
  is answered as the retry it looks like, and the note is dropped. Harmless
  while nothing offers to edit one; the moment a caption field exists, it needs
  an operation of its own.

Deliberately naive: no resume. Drop the connection at 80% of a large video and
watch it restart from zero. That experience is the justification for anything
that comes after.

## Block 4 — Background transfer

- `URLSessionConfiguration.background`
- Persisted mapping between `URLSessionTask` and Operation
- `handleEventsForBackgroundURLSession`
- Large file, app killed mid-transfer, relaunch, resumption

Background session comes before chunking, because it is a stated requirement of
the role and chunking is not.

## After, if time allows

- A build step enforcing the dependency rule. `CLAUDE.md` says Domain imports
  Foundation only, and nothing checks it: CoreData, SwiftUI and UIKit ship in
  the SDK, so `import CoreData` inside Domain compiles with no dependency
  declared and the build stays green. A grep over `Sources/Domain` is enough.
  Low priority while the layer is small enough to read in one sitting — it
  matters the day someone who has not read `CLAUDE.md` works in it.
- Chunked upload. Designed in `decisions.md` either way — an honest "here is the
  design and here is why it conflicts with background sessions" beats a
  half-working implementation.

## Cut order

If time runs short, cut media before cutting recovery. A queue that survives
termination is the thing the role is actually asking about.
