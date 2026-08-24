//
//  AssessmentRepository.swift
//  FieldAssessment
//
//  Created by MacPro on 22/08/26.
//

import Foundation

public protocol AssessmentRepository: Sendable {
    func save(_ assessment: Assessment) async throws
}
