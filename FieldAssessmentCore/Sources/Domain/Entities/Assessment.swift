//
//  Assessment.swift
//  FieldAssessment
//
//  Created by MacPro on 22/08/26.
//

import Foundation

public struct Assessment: Sendable, Equatable {
    public let id: UUID

    /// Optimistic concurrency token. A value carries the version it *will* be
    /// once written, so a write says which predecessor it expects without the
    /// caller having to pass it separately (R16).
    public let version: Int

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
                 version: Int,
                 title: String?,
                 notes: String?,
                 location: String?,
                 createdAt: Date,
                 updatedAt: Date,
                 inspector: String?,
                 status: AssessmentStatus,
                 evidences: [Evidence]) {
        self.id = id
        self.version = version
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
    /// The id is passed in rather than generated here so the use case owns
    /// identity; `internal` keeps that decision inside the module, so nothing
    /// outside can mint an assessment at all.
    ///
    /// It starts with no evidence. A creation triggered by a capture goes
    /// through `init(capturing:now:)` instead.
    init(id: UUID,
         title: String?,
         notes: String?,
         location: String?,
         inspector: String?,
         now: Date) {
        self.init(id: id,
                  version: 1,
                  title: normalized(title),
                  notes: normalized(notes),
                  location: normalized(location),
                  createdAt: now,
                  updatedAt: now,
                  inspector: normalized(inspector),
                  status: .open,
                  evidences: [])
    }

    /// Starts a new assessment from the capture that triggered it (R9).
    ///
    /// The id comes from the evidence rather than being handed in separately,
    /// because the file is filed and the evidence stamped before this value
    /// exists. Deriving it is what makes an assessment holding another
    /// assessment's evidence unrepresentable, rather than something a guard
    /// has to catch — the two ids cannot disagree if there is only one.
    init(capturing evidence: Evidence, now: Date) {
        self.init(id: evidence.assessmentId,
                  version: 1,
                  title: nil,
                  notes: nil,
                  location: nil,
                  createdAt: now,
                  updatedAt: now,
                  inspector: nil,
                  status: .open,
                  evidences: [evidence])
    }

    /// Rebuilds an assessment that already exists in storage.
    ///
    /// Only the Data layer calls this. It applies no rule and validates
    /// nothing — the record was already validated when it was written.
    package init(reconstituting id: UUID,
                 version: Int,
                 title: String?,
                 notes: String?,
                 location: String?,
                 createdAt: Date,
                 updatedAt: Date,
                 inspector: String?,
                 status: AssessmentStatus,
                 evidences: [Evidence]) {
        self.init(id: id,
                  version: version,
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

        // Whether anything changed is decided before the status is consulted.
        // An edit that asks for nothing is a repeat, and R6 refuses changes to
        // a finished record, not repeats of what it already says. R7's blur
        // flush fires on the same tap that finishes the assessment, carrying
        // text the debounce already saved: refusing it would report a failure
        // for a write that would have done nothing. `adding` and `completing`
        // order it the same way.
        guard title != self.title
                || notes != self.notes
                || location != self.location
                || inspector != self.inspector
        else { return self }

        guard status == .open else { throw AssessmentError.alreadyCompleted }

        return Assessment(id: id,
                          version: version + 1,
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

// MARK: - Completion

extension Assessment {
    /// What R4 still asks for. Empty means the inspection can be declared
    /// finished.
    ///
    /// Public because the screen needs it before the tap: it shows what is
    /// still open while the inspector fills the form, rather than only after a
    /// refusal. The order follows the form.
    public var missingForCompletion: [AssessmentRequirement] {
        var missing: [AssessmentRequirement] = []
        if location == nil { missing.append(.location) }
        if inspector == nil { missing.append(.inspector) }
        if evidences.isEmpty { missing.append(.evidence) }
        return missing
    }

    /// Declares the inspection finished (R3). The only producer of
    /// `.completed`.
    ///
    /// Returns `self` on an assessment that is already completed. A second tap
    /// on Finish asks for nothing the first did not already do, so it is a
    /// repeat rather than a refusal — unlike an edit, which wants something
    /// R6 will not give.
    ///
    /// Throws `incomplete` carrying everything that is missing at once (R5).
    func completing(at now: Date) throws -> Assessment {
        guard status == .open else { return self }

        let missing = missingForCompletion
        guard missing.isEmpty else { throw AssessmentError.incomplete(missing) }

        return Assessment(id: id,
                          version: version + 1,
                          title: title,
                          notes: notes,
                          location: location,
                          createdAt: createdAt,
                          updatedAt: now,
                          inspector: inspector,
                          status: .completed,
                          evidences: evidences)
    }
}

// MARK: - Evidence

extension Assessment {
    /// Attaches a newly captured piece of evidence (R9), moving `updatedAt`.
    ///
    /// Refuses on a completed assessment for the same reason editing does
    /// (R6), and refuses evidence stamped with another assessment's id.
    ///
    /// Evidence already attached is returned untouched rather than added
    /// again. A capture keeps its id across attempts, so a caller retrying one
    /// that actually landed must not end up with two copies of it — and the
    /// check comes before the status guard, because that retry is not a change
    /// and must not be refused on an assessment completed since.
    ///
    /// Untouched is literal. A second call carrying the same evidence id with
    /// a different type or note gets the record as it stands, and what it
    /// carried is dropped: a repeat is the first attempt continuing, and the
    /// first attempt is what decided. Changing what an attached piece of
    /// evidence says needs its own operation, and nothing offers to yet.
    ///
    /// The ownership guard below cannot fire from a use case, because a
    /// capture names its assessment and the use cases commit against that same
    /// id (decision 23). It stays as the entity's own invariant, for callers
    /// that build an `Evidence` by hand.
    func adding(_ evidence: Evidence, at now: Date) throws -> Assessment {
        guard !evidences.contains(where: { $0.id == evidence.id }) else { return self }
        guard status == .open else { throw AssessmentError.alreadyCompleted }
        guard evidence.assessmentId == id else {
            throw AssessmentError.evidenceBelongsToAnotherAssessment
        }

        return Assessment(id: id,
                          version: version + 1,
                          title: title,
                          notes: notes,
                          location: location,
                          createdAt: createdAt,
                          updatedAt: now,
                          inspector: inspector,
                          status: status,
                          evidences: evidences + [evidence])
    }
}
