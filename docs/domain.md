# Domain

Business rules. No implementation detail — this document should stay true
regardless of how it gets coded.

## What the app does

An inspector goes to a site, creates an inspection, fills in who and where,
attaches evidence of what was found, and marks it finished. The device may have
no connectivity for the whole visit. Nothing about that experience is allowed to
depend on the network.

Finished inspections reach the server later, on their own.

## Entities

### Assessment

A single inspection performed by one inspector at one location.

| Field | Required | Meaning |
|---|---|---|
| id | yes | Identity. Created on the device, offline, at the moment of creation. |
| status | yes | `open` or `completed`. |
| title | no | Short label the inspector gives the inspection. |
| location | to complete | Where the inspection happened. |
| inspector | to complete | Who performed it. |
| notes | no | Free text. |
| createdAt | yes | When the inspection was started. |
| updatedAt | yes | Last local change. |
| evidences | to complete | At least one is required to finish. |

There is no separate server identifier. The id created on the device is the id
everywhere, for the entity's whole life.

### Evidence

A piece of proof captured during the inspection: a photo, a video, or an audio
recording.

| Field | Required | Meaning |
|---|---|---|
| id | yes | Identity, created on the device. |
| assessmentId | yes | Which inspection it belongs to. |
| type | yes | image, video or audio. |
| fileName | yes | Which file on disk holds the content. |
| notes | no | What the inspector wants to say about this specific piece of evidence. |
| createdAt | yes | When it was captured. |

Evidence belongs to exactly one assessment and is never shared between them.

The recorded file itself is not part of the database. The database records that
the evidence exists; the file lives on disk.

## Rules

**R1. An assessment starts open.**
Creation requires nothing. An inspector can start an inspection with the screen
empty and fill it in later.

**R2. Open means unfinished, not untouched.**
An assessment can stay open for seconds or for days, across app restarts. The
only thing it says is that the inspector has not declared it finished.

**R3. Finishing is an operation, not a field change.**
Nothing in the app may set the status directly. Finishing goes through a single
domain operation that validates first and refuses if the requirements are not
met.

**R4. An assessment can only be completed when it has a location, an inspector,
and at least one piece of evidence.**
Notes are optional.

**R5. Validation reports everything that is missing at once.**
If two requirements are unmet, the inspector sees both, rather than discovering
them one failed attempt at a time.

**R6. Completion is final.**
A completed assessment is not reopened or edited. It is a submitted record.

**R7. Work in progress survives a closed app.**
There is no Save button. Changes persist while the inspector works, not when
they leave the screen.

The gap between a keystroke and a committed write cannot be zero — some window
always exists. What is promised is that the window is short, and that it is
closed at the two moments where loss would actually be noticed: when a field is
left, and when the app goes to the background. An abrupt kill in the middle of
continuous typing can cost the last moment of it. Nothing already finished is at
risk.

**R8. An empty assessment is not stored.**
Opening the new-inspection screen and walking away leaves nothing behind. The
record comes into existence on the first real input — a filled field or a
captured piece of evidence — not on the first tap.

**R9. Evidence is saved the moment it is captured.**
Unlike text, a captured photo or video is never held pending. It is recorded
immediately, and counts as real input for the rule above.

**R10. Only completed assessments are sent to the server.**
Drafts are local, always. Nothing about an open assessment reaches the network.

**R11. Business state and delivery state are different things.**
Whether the inspector has finished the inspection, and whether that inspection
has reached the server, are two independent facts. A finished inspection sitting
unsent is a normal, valid, expected state — not an error.

**R12. Delivery state is never edited by hand.**
It is not something the app writes down. It is read from the work still
outstanding: anything failed makes the assessment failed, anything in progress
makes it syncing, anything waiting makes it pending, and nothing outstanding
means delivered.

**R13. An assessment is only delivered when everything in it is delivered.**
The record and all of its evidence. A completed record whose video failed to
upload is failed, not delivered.

**R14. A draft has no delivery state at all.**
An open assessment shows nothing. It is not "waiting to sync" — it is not meant
to sync.

**R15. Delivering the same thing twice must not create two of it.**
The network can lose a response after the server has already accepted the work.
The app cannot tell that apart from a genuine failure, so it will retry. The
system has to absorb that without duplicating anything.

## Deliberately out of scope

Stated as choices, not gaps.

- **Assessments are only created on the device.** There is no back office
  assigning work, and no server-to-client sync of assessment data.
- **No conflict handling.** One inspector, one device, one owner per record.
  Nothing else writes to an assessment, so there is nothing to reconcile.
- **No questionnaire.** Title, location, inspector, notes and evidence are the
  whole form. The domain stays small on purpose.
- **No users, roles or permissions.**
