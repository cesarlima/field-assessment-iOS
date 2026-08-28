//
//  EvidenceFileStore.swift
//  FieldAssessment
//
//  Created by MacPro on 24/08/26.
//

import Foundation

/// What filing a capture produced.
public struct StoredFile: Sendable, Equatable {
    /// The name to record on the evidence row. A name, never a path — the
    /// container the file lives in is resolved at runtime.
    public let name: String

    /// Whether this call is what put the file in the evidence directory.
    ///
    /// `false` means a file was already filed under that id and this call
    /// adopted it, so something else got there first and may already hold an
    /// evidence row naming it. That is the whole question behind "is deleting
    /// this safe": only a call that moved the file can know nothing else
    /// points at it.
    public let wasMoved: Bool

    public init(name: String, wasMoved: Bool) {
        self.name = name
        self.wasMoved = wasMoved
    }
}

public protocol EvidenceFileStore: Sendable {
    /// Moves the captured file into the evidence directory under a name
    /// derived from `file.id`.
    ///
    /// If a file for that id is already there, the move already happened: the
    /// existing file is adopted, its name returned with `wasMoved: false`, and
    /// the source is not touched. That is what lets a caller retry the same
    /// capture after a failed write, when the source it started from is gone.
    ///
    /// The move is what makes the file durable, so it has to finish before the
    /// evidence row is written. A crash in between leaves a file with no row,
    /// which the name identifies and a launch sweep can delete; the reverse
    /// order would leave a row pointing at nothing, which is lost field
    /// evidence.
    func store(_ file: CapturedFile) async throws -> StoredFile

    /// Deletes the file filed under `id`.
    ///
    /// Only for a capture this call moved in and that was then refused for
    /// good: it will never be attached to anything, so nothing will ever point
    /// at the file. Never for a failure that can be retried — after the move,
    /// that file is the only copy of the capture left — and never for a file
    /// `store` reported as adopted, because whatever filed it first may
    /// already name it.
    func remove(_ id: UUID) async throws
}
