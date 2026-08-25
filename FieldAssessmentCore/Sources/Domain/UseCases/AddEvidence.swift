//
//  AddEvidence.swift
//  FieldAssessment
//
//  Created by MacPro on 25/08/26.
//

import Foundation

/// Records a capture against an assessment that already exists (R9).
///
/// The first capture on an empty screen goes through `CreateAssessment`
/// instead, because there is no record yet to attach to and creating one
/// separately would open the gap R8 forbids.
public struct AddEvidence: Sendable {
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

    @discardableResult
    public func execute(assessmentId: UUID,
                        capturing file: CapturedFile,
                        type: EvidenceType,
                        evidenceNotes: String? = nil) async throws -> Assessment {
        // An id that does not exist is a caller bug rather than a field
        // condition, and failing on it here avoids moving a large file for
        // nothing.
        //
        // Status is deliberately not checked. `adding` is the only authority
        // on it: it alone sees fresh state, and it alone knows that a retry of
        // a capture that already landed is a no-op rather than a refusal. A
        // copy of that guard here would refuse the retry before `adding` ever
        // ran, and report a failure for a photo that is already attached.
        _ = try await repository.fetch(id: assessmentId)

        let fileName = try await files.store(file)

        let capturedAt = now()
        let evidence = Evidence(id: file.id,
                                assessmentId: assessmentId,
                                type: type,
                                fileName: fileName,
                                notes: normalized(evidenceNotes),
                                createdAt: capturedAt)

        // The media is filed and the id came in with the capture, so a retry
        // from here is pure in-memory work: no second move, no new orphan.
        //
        // `updatedAt` is stamped inside the closure, by the attempt that
        // actually lands. Reusing `capturedAt` would let a retry write a time
        // older than the edit it just rebased on, and a list ordered by last
        // local change would show the assessment before a note it contains.
        // `evidence.createdAt` keeps `capturedAt`: that is when the photo was
        // taken, and no retry changes it.
        let now = self.now
        do {
            return try await commit(assessmentId, in: repository) { current in
                try current.adding(evidence, at: now())
            }
        } catch let error as AssessmentError {
            // A refusal is final — the capture will never be attached, so
            // nothing will ever point at the file it moved. This is the one
            // place deleting media destroys no evidence. Every other failure
            // leaves the file where it is, because it is the only copy left
            // and the caller can try the same capture again.
            try? await files.remove(file.id)
            throw error
        }
    }
}
