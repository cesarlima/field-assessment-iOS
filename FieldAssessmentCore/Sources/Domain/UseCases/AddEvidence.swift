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
        // Advisory, not authoritative. Filing the media first is what keeps a
        // crash from leaving a row pointing at nothing, so a refusal
        // discovered afterwards would already have moved a file nothing will
        // ever reference. This reads a snapshot that may be stale by the time
        // the write happens; the guard that decides is the one inside
        // `adding`, re-run against fresh state on every attempt.
        let preview = try await repository.fetch(id: assessmentId)
        guard preview.status == .open else {
            throw AssessmentError.alreadyCompleted
        }

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
        do {
            return try await commit(assessmentId, in: repository) { current in
                try current.adding(evidence, at: capturedAt)
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
