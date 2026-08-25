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

    /// The one place fields are assigned. Every entry point below funnels
    /// through here, so there is a single definition of what an assessment is
    /// made of.
    private init(id: UUID,
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
        self.init(id: id,
                  title: normalized(title),
                  notes: normalized(notes),
                  location: normalized(location),
                  createdAt: now,
                  updatedAt: now,
                  inspector: normalized(inspector),
                  status: .open,
                  evidences: evidences)
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
        self.init(id: id,
                  title: title,
                  notes: notes,
                  location: location,
                  createdAt: createdAt,
                  updatedAt: updatedAt,
                  inspector: inspector,
                  status: status,
                  evidences: evidences)
    }
}

// MARK: - Editing

extension Assessment {
    /// Applies a draft edit, moving `updatedAt` to `now`.
    ///
    /// Throws `alreadyCompleted` when the assessment is no longer a draft
    /// (R6). Without this guard a finished record could drift away from what
    /// was already pushed, and sync is push-only, so nothing would reconcile
    /// it.
    ///
    /// Returns `self` untouched when the edit changes nothing, so a redundant
    /// autosave does not move `updatedAt` — that field means last local
    /// change, not last keystroke.
    func applying(_ edit: AssessmentEdit, at now: Date) throws -> Assessment {
        try applying([edit], at: now)
    }

    /// Applies several edits as one change. A debounced field can flush
    /// everything the inspector touched in a single write.
    func applying(_ edits: [AssessmentEdit], at now: Date) throws -> Assessment {
        guard status == .open else { throw AssessmentError.alreadyCompleted }

        var title = self.title
        var notes = self.notes
        var location = self.location
        var inspector = self.inspector

        for edit in edits {
            switch edit {
            case .title(let value): title = normalized(value)
            case .notes(let value): notes = normalized(value)
            case .location(let value): location = normalized(value)
            case .inspector(let value): inspector = normalized(value)
            }
        }

        guard title != self.title
                || notes != self.notes
                || location != self.location
                || inspector != self.inspector
        else { return self }

        return Assessment(id: id,
                          title: title,
                          notes: notes,
                          location: location,
                          createdAt: createdAt,
                          updatedAt: now,
                          inspector: inspector,
                          status: status,
                          evidences: evidences)
    }
}
