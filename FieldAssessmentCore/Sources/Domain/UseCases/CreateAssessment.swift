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
    public func execute(title: String? = nil,
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

        let assessment = Assessment(id: UUID(),
                                    title: title,
                                    notes: notes,
                                    location: location,
                                    inspector: inspector,
                                    evidences: [],
                                    now: now())
        try await repository.save(assessment)
        return assessment
    }

    /// First input is a capture (R9).
    ///
    /// The file is filed before the record is built, so the only crash window
    /// leaves an orphan file rather than a row pointing at nothing. The
    /// assessment and its first evidence are then written together, so the app
    /// can never be terminated into an empty assessment.
    public func execute(capturing file: CapturedFile,
                        type: EvidenceType,
                        evidenceNotes: String? = nil) async throws -> Assessment {
        let assessmentId = UUID()
        let evidenceId = UUID()

        let fileName = try await files.store(file, as: evidenceId)

        let capturedAt = now()
        let evidence = Evidence(id: evidenceId,
                                assessmentId: assessmentId,
                                type: type,
                                fileName: fileName,
                                notes: normalized(evidenceNotes),
                                createdAt: capturedAt)

        let assessment = Assessment(id: assessmentId,
                                    title: nil,
                                    notes: nil,
                                    location: nil,
                                    inspector: nil,
                                    evidences: [evidence],
                                    now: capturedAt)
        try await repository.save(assessment)
        return assessment
    }
}

/// Trimmed, or nil when nothing but whitespace is left.
private func normalized(_ value: String?) -> String? {
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
          !trimmed.isEmpty else { return nil }
    return trimmed
}
