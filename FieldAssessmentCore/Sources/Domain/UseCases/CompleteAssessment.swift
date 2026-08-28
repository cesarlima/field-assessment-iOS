//
//  CompleteAssessment.swift
//  FieldAssessment
//
//  Created by MacPro on 26/08/26.
//

import Foundation

/// Declares an inspection finished (R3).
///
/// Nothing else in the app may set the status. Completing validates first and
/// refuses with everything that is missing, so the inspector is never sent
/// back one requirement at a time.
public struct CompleteAssessment: Sendable {
    private let repository: AssessmentRepository
    private let now: @Sendable () -> Date

    public init(repository: AssessmentRepository,
                now: @Sendable @escaping () -> Date = { Date() }) {
        self.repository = repository
        self.now = now
    }

    @discardableResult
    public func execute(id: UUID) async throws -> Assessment {
        let now = self.now
        return try await commit(id, in: repository) { current in
            try current.completing(at: now())
        }
    }
}
