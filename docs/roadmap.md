# Roadmap

Four blocks. Not fifteen milestones — the value is concentrated, and spreading it
thin produces four half-finished features instead of one complete story.

Build in problem-first order: implement the naive version, feel the failure, then
engineer the real solution. That sequence is what turns a copied pattern into a
decision you can defend.

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
