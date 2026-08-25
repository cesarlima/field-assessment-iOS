//
//  Assessment.swift
//  FieldAssessment
//
//  Created by MacPro on 22/08/26.
//

import Foundation

public struct Assessment: Sendable, Equatable {
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
    ///
    /// The id is passed in rather than generated here because a first capture
    /// has to stamp its `Evidence.assessmentId` before this value exists. The
    /// use case owns that ordering; `internal` keeps the decision inside the
    /// module, so nothing outside can mint an assessment at all.
    init(id: UUID,
         title: String?,
         notes: String?,
         location: String?,
         inspector: String?,
         evidences: [Evidence],
         now: Date) {
        self.id = id
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
