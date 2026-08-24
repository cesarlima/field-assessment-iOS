//
//  CreateAssessment.swift
//  FieldAssessment
//
//  Created by MacPro on 22/08/26.
//

import Foundation

public struct CreateAssessment: Sendable {
    private let repository: AssessmentRepository
    
    public init(repository: AssessmentRepository) {
        self.repository = repository
    }
    
    public func execute(_ assessment: Assessment) async throws {
        try await repository.save(assessment)
    }
}
