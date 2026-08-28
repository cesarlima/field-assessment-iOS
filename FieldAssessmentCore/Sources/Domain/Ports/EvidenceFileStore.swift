//
//  EvidenceFileStore.swift
//  FieldAssessment
//
//  Created by MacPro on 24/08/26.
//

import Foundation

public protocol EvidenceFileStore: Sendable {
    /// Moves the captured file into the evidence directory under a name
    /// derived from `file.id`.
    ///
    /// If a file for that id is already there, the move already happened: the
    /// existing file is adopted, its name returned, and the source is not
    /// touched. That is what lets a caller retry the same capture after a
    /// failed write, when the source it started from is gone.
    ///
    /// The move is what makes the file durable, so it has to finish before the
    /// evidence row is written. A crash in between leaves a file with no row,
    /// which the name identifies and a launch sweep can delete; the reverse
    /// order would leave a row pointing at nothing, which is lost field
    /// evidence.
    func store(_ file: CapturedFile) async throws -> String

    /// Deletes the file filed under `id`.
    ///
    /// Only for a capture that was refused for good: it will never be attached
    /// to anything, so nothing will ever point at the file. A capture belongs
    /// to one assessment, and `adding` refuses only after finding the evidence
    /// is not attached to it, so a refusal means no row anywhere names this
    /// file.
    ///
    /// Never for a failure that can be retried — after the move, that file is
    /// the only copy of the capture left.
    func remove(_ id: UUID) async throws
}
