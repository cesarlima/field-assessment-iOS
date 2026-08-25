//
//  AssessmentRepository.swift
//  FieldAssessment
//
//  Created by MacPro on 22/08/26.
//

import Foundation

public enum AssessmentRepositoryError: Error, Equatable, Sendable {
    case notFound(UUID)
}

public protocol AssessmentRepository: Sendable {
    /// Writes a new assessment and everything it carries in one transaction.
    ///
    /// Creating a record and recording its first evidence is a single write:
    /// an app terminated between two of them would leave the empty assessment
    /// R8 forbids.
    func insert(_ assessment: Assessment) async throws

    /// Overwrites an existing assessment.
    ///
    /// Separate from `insert` on purpose. An upsert here would silently
    /// recreate a row that something else had removed, and would hide which of
    /// the two things actually happened.
    ///
    /// Throws `notFound` when no record carries this id.
    func update(_ assessment: Assessment) async throws

    /// Throws `notFound` when no record carries this id.
    func fetch(id: UUID) async throws -> Assessment

    func fetchAll() async throws -> [Assessment]
}
