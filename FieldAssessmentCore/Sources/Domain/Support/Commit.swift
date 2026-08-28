//
//  Commit.swift
//  FieldAssessment
//
//  Created by MacPro on 25/08/26.
//

import Foundation

/// Reads, transforms and writes an assessment under compare-and-set, retrying
/// when something else wrote first.
///
/// `transform` runs again on each attempt, against the value just read. That
/// is what stops a guard inside it from judging a stale snapshot: a completion
/// that landed during the first attempt is visible to the second, which then
/// refuses instead of overwriting it.
///
/// Retrying is cheap on purpose. Everything expensive — filing media, minting
/// ids — happens before the caller gets here, so a second attempt is pure
/// in-memory work and moves no files.
func commit(_ id: UUID,
            in repository: AssessmentRepository,
            attempts: Int = 5,
            _ transform: (Assessment) throws -> Assessment) async throws -> Assessment {
    var attempt = 1
    while true {
        let current = try await repository.fetch(id: id)
        let next = try transform(current)

        // Nothing changed, so there is nothing to race over.
        guard next != current else { return current }

        do {
            try await repository.update(next)
            return next
        } catch let error as AssessmentRepositoryError {
            guard case .staleWrite = error, attempt < attempts else { throw error }
            attempt += 1
        }
    }
}
