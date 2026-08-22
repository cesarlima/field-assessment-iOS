//
//  Evidence.swift
//  FieldAssessment
//
//  Created by MacPro on 22/08/26.
//

import Foundation

public struct Evidence: Sendable {
    public let id: UUID
    public let fileName: String
    public let createdAt: Date
    public let type: EvidenceType
    
    public init(id: UUID,
                fileName: String,
                createdAt: Date,
                type: EvidenceType) {
        self.id = id
        self.fileName = fileName
        self.createdAt = createdAt
        self.type = type
    }
}
