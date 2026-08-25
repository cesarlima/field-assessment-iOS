//
//  UpdateAssessment.swift
//  FieldAssessment
//
//  Created by MacPro on 24/08/26.
//

import Foundation

/// Records a change to a draft while the inspector works (R7).
///
/// Kept apart from `CreateAssessment` because the two enforce opposite rules:
/// creation refuses an empty input (R8), editing refuses a finished record
/// (R6). One use case that sometimes rejects one and sometimes the other would
/// be harder to follow than the caller knowing which of the two it wants.
public struct UpdateAssessment: Sendable {
    private let repository: AssessmentRepository
    private let now: @Sendable () -> Date

    public init(repository: AssessmentRepository,
                now: @Sendable @escaping () -> Date = { Date() }) {
        self.repository = repository
        self.now = now
    }

    @discardableResult
    public func execute(id: UUID, _ edit: AssessmentEdit) async throws -> Assessment {
        try await execute(id: id, [edit])
    }

    /// Several edits land as one write, so a debounced screen can flush every
    /// field the inspector touched at once.
    ///
    /// Nothing is written when the edits change nothing. A redundant autosave
    /// is common — the same text flushed twice — and it should not move
    /// `updatedAt` or produce a pointless transaction.
    @discardableResult
    public func execute(id: UUID, _ edits: [AssessmentEdit]) async throws -> Assessment {
        let current = try await repository.fetch(id: id)
        let updated = try current.applying(edits, at: now())

        guard updated != current else { return current }

        try await repository.update(updated)
        return updated
    }
}
