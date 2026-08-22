//
//  Assessment.swift
//  FieldAssessment
//
//  Created by MacPro on 22/08/26.
//

import Foundation

public struct Assessment: Sendable {
    public let id: UUID
    public let notes: String?
    public let location: String
    public let createdAt: Date
    public let updatedAt: Date?
    public let inspector: String
    public let status: AssessmentStatus
    public let evidences: [Evidence]
    
    public init(id: UUID? = nil,
                notes: String?,
                location: String,
                createdAt: Date,
                updatedAt: Date?,
                inspector: String,
                status: AssessmentStatus,
                evidences: [Evidence]) {
        self.id = id ?? UUID()
        self.notes = notes
        self.location = location
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.inspector = inspector
        self.status = status
        self.evidences = evidences
    }
}
