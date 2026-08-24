//
//  Assessment.swift
//  FieldAssessment
//
//  Created by MacPro on 22/08/26.
//

import Foundation

public struct Assessment: Sendable {
    public let id: UUID
    public let title: String?
    public let notes: String?
    public let location: String?
    public let createdAt: Date
    public let updatedAt: Date
    public let inspector: String?
    public let status: AssessmentStatus
    public let evidences: [Evidence]
    
    /// Starts a new assessment on the device.
    ///
    /// The status is not a parameter: an assessment always starts `open` (R1),
    /// and only the completion operation may move it (R3).
    init(title: String? = nil,
         notes: String? = nil,
         location: String? = nil,
         inspector: String? = nil,
         evidences: [Evidence] = [],
         now: Date) {
        self.id = UUID()
        self.title = title
        self.notes = notes
        self.location = location
        self.createdAt = now
        self.updatedAt = now
        self.inspector = inspector
        self.status = .open
        self.evidences = evidences
    }
    
    /// Rebuilds an assessment that already exists in storage.
    ///
    /// Only the Data layer calls this. It applies no rule and validates
    /// nothing — the record was already validated when it was written.
    package init(reconstituting id: UUID,
                 title: String?,
                 notes: String?,
                 location: String?,
                 createdAt: Date,
                 updatedAt: Date,
                 inspector: String?,
                 status: AssessmentStatus,
                 evidences: [Evidence]) {
        self.id = id
        self.title = title
        self.notes = notes
        self.location = location
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.inspector = inspector
        self.status = status
        self.evidences = evidences
    }
}
