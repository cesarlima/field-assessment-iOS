//
//  CreateAssessment.swift
//  FieldAssessment
//
//  Created by MacPro on 22/08/26.
//

import Foundation

public enum CreateAssessmentError: Error, Equatable, Sendable {
    /// Nothing was actually entered, so there is nothing to store (R8).
    case noInput
}

/// Brings an assessment into existence on its first real input.
///
/// There are two triggers and no third: the inspector typed something, or the
/// inspector captured something. Neither overload can be called empty, which
/// is how R8 is enforced by shape rather than by a runtime check.
///
/// The id comes from the caller, minted when the screen opens — on the text
/// path as a parameter, on the capture path inside the capture itself.
/// Nothing is stored then, so R8 still holds: an id in memory is not a record.
/// What it buys is that every attempt at the same creation carries the same
/// identity, so the second one lands on a primary key that is already taken
/// instead of writing a second assessment. Without it, a button tapped twice
/// produces two records sharing one evidence id and one file on disk, and
/// deleting either one takes the other's photo with it.
///
/// An id that is already taken is never an error here. It means another
/// attempt at this same creation got there first, and what this one was
/// carrying is merged into the record that won rather than discarded.
public struct CreateAssessment: Sendable {
    private let repository: AssessmentRepository
    private let files: EvidenceFileStore
    private let now: @Sendable () -> Date

    public init(repository: AssessmentRepository,
                files: EvidenceFileStore,
                now: @Sendable @escaping () -> Date = { Date() }) {
        self.repository = repository
        self.files = files
        self.now = now
    }

    /// First input is text.
    ///
    /// Throws `noInput` when every field is empty or only whitespace: a typed
    /// space is not a real input, and R8 says an empty assessment is not
    /// stored.
    public func execute(id: UUID,
                        title: String? = nil,
                        notes: String? = nil,
                        location: String? = nil,
                        inspector: String? = nil) async throws -> Assessment {
        let title = normalized(title)
        let notes = normalized(notes)
        let location = normalized(location)
        let inspector = normalized(inspector)

        guard title != nil || notes != nil || location != nil || inspector != nil else {
            throw CreateAssessmentError.noInput
        }

        let assessment = Assessment(id: id,
                                    title: title,
                                    notes: notes,
                                    location: location,
                                    inspector: inspector,
                                    now: now())
        do {
            try await repository.insert(assessment)
            return assessment
        } catch AssessmentRepositoryError.alreadyExists {
            // Only the fields this call was given. A `nil` here means the
            // caller said nothing about that field, not that it should be
            // cleared — clearing is `UpdateAssessment`'s job and says so with
            // an explicit edit.
            var edits: [AssessmentEdit] = []
            if let title { edits.append(.title(title)) }
            if let notes { edits.append(.notes(notes)) }
            if let location { edits.append(.location(location)) }
            if let inspector { edits.append(.inspector(inspector)) }
            return try await merge(edits, into: id)
        }
    }

    /// First input is a capture (R9).
    ///
    /// The file is filed before the record is built, so the only crash window
    /// leaves an orphan file rather than a row pointing at nothing. The
    /// assessment and its first evidence are then written together, so the app
    /// can never be terminated into an empty assessment.
    ///
    /// A failure leaves the media filed. Calling again with the same capture
    /// picks it up instead of moving it twice.
    ///
    /// The assessment is not named separately: it comes from the capture,
    /// which was taken for one and only one.
    public func execute(capturing file: CapturedFile,
                        type: EvidenceType,
                        evidenceNotes: String? = nil) async throws -> Assessment {
        let fileName = try await files.store(file)

        let capturedAt = now()
        let evidence = Evidence(id: file.id,
                                assessmentId: file.assessmentId,
                                type: type,
                                fileName: fileName,
                                notes: normalized(evidenceNotes),
                                createdAt: capturedAt)

        let assessment = Assessment(capturing: evidence, now: capturedAt)
        do {
            try await repository.insert(assessment)
            return assessment
        } catch AssessmentRepositoryError.alreadyExists {
            return try await attach(evidence)
        }
    }

    /// Attaches the capture to whichever record took the id first.
    ///
    /// Returning that record instead would report success while the photo is
    /// dropped: `store` has already moved the capture out of temporary
    /// storage, so nothing else is holding it and nobody has a reason to try
    /// again. The file would sit on disk with no row naming it until the
    /// launch sweep deleted it.
    ///
    /// This is the same write `AddEvidence` makes, so a repeat of this same
    /// capture lands here too and `adding` answers it with the record
    /// untouched.
    private func attach(_ evidence: Evidence) async throws -> Assessment {
        let now = self.now
        do {
            return try await commit(evidence.assessmentId, in: repository) { current in
                try current.adding(evidence, at: now())
            }
        } catch AssessmentError.alreadyCompleted {
            // The record that won has since been completed, so it will never
            // take this capture — and the capture names that record, so there
            // is no other assessment it could already belong to. No row
            // anywhere names the file. Same reasoning as `AddEvidence`.
            try? await files.remove(evidence.id)
            throw AssessmentError.alreadyCompleted
        }
    }

    /// Applies what this call was asked to create onto the record that took
    /// the id first.
    ///
    /// Returning that record instead would discard the input. The screen
    /// usually still holds it and flushes again — but not always: leaving the
    /// screen fires the blur flush and the background flush together, and
    /// whichever loses the primary key has no next flush to fall back on,
    /// because the app is suspending. What it was carrying would simply be
    /// gone.
    ///
    /// Throws `alreadyCompleted` when the record that won has since been
    /// finished and this call actually asks to change it, which is R6. A flush
    /// carrying what the record already says changes nothing and is not
    /// refused.
    private func merge(_ edits: [AssessmentEdit], into id: UUID) async throws -> Assessment {
        let now = self.now
        return try await commit(id, in: repository) { current in
            try current.applying(edits, at: now())
        }
    }
}
