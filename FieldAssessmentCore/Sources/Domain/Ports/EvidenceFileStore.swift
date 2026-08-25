//
//  EvidenceFileStore.swift
//  FieldAssessment
//
//  Created by MacPro on 24/08/26.
//

import Foundation

public protocol EvidenceFileStore: Sendable {
    /// Moves the captured file into the evidence directory under a name
    /// derived from `id`, and returns that name.
    ///
    /// The move is what makes the file durable, so it has to finish before the
    /// evidence row is written. A crash after this returns leaves an orphan
    /// file, which is recoverable; the reverse order would leave a row pointing
    /// at nothing, which is lost field evidence.
    func store(_ file: CapturedFile, as id: UUID) async throws -> String
}
