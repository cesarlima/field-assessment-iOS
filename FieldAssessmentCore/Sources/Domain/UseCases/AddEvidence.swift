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
        let assessment = try await repository.fetch(id: assessmentId)

        // Checked here as well as inside `adding`, and not for belt and
        // braces: filing the media first is what keeps a crash from leaving a
        // row pointing at nothing, so a refusal discovered afterwards would
        // have already moved a file that nothing will ever reference. The
        // entity keeps the rule; this keeps the orphan from being created on a
        // path already known to fail.
        guard assessment.status == .open else {
            throw AssessmentError.alreadyCompleted
        }

        let evidenceId = UUID()
        let fileName = try await files.store(file, as: evidenceId)

        let capturedAt = now()
        let evidence = Evidence(id: evidenceId,
                                assessmentId: assessmentId,
                                type: type,
                                fileName: fileName,
                                notes: normalized(evidenceNotes),
                                createdAt: capturedAt)

        let updated = try assessment.adding(evidence, at: capturedAt)
        try await repository.update(updated)
        return updated
    }
}
