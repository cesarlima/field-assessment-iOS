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
/// The id comes from the caller, minted when the screen opens. Nothing is
/// stored then, so R8 still holds — an id in memory is not a record. What it
/// buys is that every attempt at the same creation carries the same identity,
/// so the second one lands on a primary key that is already taken instead of
/// writing a second assessment. Without it, a button tapped twice produces two
/// records sharing one evidence id and one file on disk, and deleting either
/// one takes the other's photo with it.
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
        return try await insert(assessment)
    }

    /// First input is a capture (R9).
    ///
    /// The file is filed before the record is built, so the only crash window
    /// leaves an orphan file rather than a row pointing at nothing. The
    /// assessment and its first evidence are then written together, so the app
    /// can never be terminated into an empty assessment.
    ///
    /// Nothing here is a final refusal — an insert either lands or fails for a
    /// reason worth retrying — so a failure leaves the media filed. Calling
    /// again with the same capture picks it up instead of moving it twice.
    public func execute(id: UUID,
                        capturing file: CapturedFile,
                        type: EvidenceType,
                        evidenceNotes: String? = nil) async throws -> Assessment {
        let fileName = try await files.store(file)

        let capturedAt = now()
        let evidence = Evidence(id: file.id,
                                assessmentId: id,
                                type: type,
                                fileName: fileName,
                                notes: normalized(evidenceNotes),
                                createdAt: capturedAt)

        let assessment = Assessment(capturing: evidence, now: capturedAt)
        return try await insert(assessment)
    }

    /// Writes the record, treating an id that is already taken as this same
    /// creation having landed already.
    ///
    /// That is the only thing it can be: the caller owns the id and reuses it
    /// across attempts, so the record sitting there is the one this call was
    /// trying to write. Returning it makes a repeat end in success with one
    /// record, the same way a repeated capture ends attached once.
    ///
    /// The stored record is returned rather than the one just built, because
    /// the stored one is what exists. A create that ran twice with different
    /// text loses nothing durable: the screen still holds what was typed, now
    /// knows the record exists, and its next flush goes through
    /// `UpdateAssessment`.
    ///
    /// The media is never deleted here. On a capture, the record that already
    /// exists points at the very file this call filed.
    private func insert(_ assessment: Assessment) async throws -> Assessment {
        do {
            try await repository.insert(assessment)
            return assessment
        } catch AssessmentRepositoryError.alreadyExists {
            return try await repository.fetch(id: assessment.id)
        }
    }
}
