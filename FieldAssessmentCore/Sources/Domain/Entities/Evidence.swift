//
//  Evidence.swift
//  FieldAssessment
//
//  Created by MacPro on 22/08/26.
//

import Foundation

public struct Evidence: Sendable, Equatable {
    public let id: UUID
    public let assessmentId: UUID
    public let type: EvidenceType
    public let fileName: String
    public let notes: String?
    public let createdAt: Date

    /// One initializer, unlike `Assessment`: creating a piece of evidence and
    /// restoring one from storage produce the same value from the same fields.
    /// There is nothing for creation to derive, so there is nothing to split.
    ///
    /// `package` keeps it inside the Core package — the Data layer maps rows
    /// back through it, Presentation never builds one.
    package init(id: UUID,
                 assessmentId: UUID,
                 type: EvidenceType,
                 fileName: String,
                 notes: String?,
                 createdAt: Date) {
        self.id = id
        self.assessmentId = assessmentId
        self.type = type
        self.fileName = fileName
        self.notes = notes
        self.createdAt = createdAt
    }
}
