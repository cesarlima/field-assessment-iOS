//
//  AssessmentRepository.swift
//  FieldAssessment
//
//  Created by MacPro on 22/08/26.
//

import Foundation

public enum AssessmentRepositoryError: Error, Equatable, Sendable {
    case notFound(UUID)

    /// The record moved on between being read and being written. Nothing was
    /// written (R16).
    ///
    /// `expected` and `found` are carried so a failure can be diagnosed rather
    /// than guessed at — without them a test can only assert that something
    /// went wrong.
    case staleWrite(id: UUID, expected: Int, found: Int)

    /// A record already carries this id, so nothing was written.
    ///
    /// The caller owns the id and reuses it across attempts, so this is the
    /// normal answer to a create that ran twice — a button tapped twice, a
    /// retry racing the attempt it was retrying — not a collision between two
    /// different assessments. Two UUIDs do not collide.
    case alreadyExists(UUID)
}

public protocol AssessmentRepository: Sendable {
    /// Writes a new assessment and everything it carries in one transaction.
    ///
    /// Creating a record and recording its first evidence is a single write:
    /// an app terminated between two of them would leave the empty assessment
    /// R8 forbids.
    ///
    /// Throws `alreadyExists` when the id is taken, and writes nothing. The
    /// primary key is what decides, so two creates running at once cannot both
    /// win: checking first and inserting after would leave a window where
    /// neither sees the other.
    func insert(_ assessment: Assessment) async throws

    /// Writes an existing assessment, if nothing else wrote first.
    ///
    /// Compare-and-set: the write lands only when the stored version is
    /// exactly `assessment.version - 1`, and stores `assessment.version`.
    /// Otherwise it throws `staleWrite` and changes nothing.
    ///
    /// A last-writer-wins overwrite would be lossy by construction here. Every
    /// caller reads, computes, and writes back the whole aggregate, so without
    /// this check a debounced note flushed during a capture — or a completion
    /// landing mid-write — would be silently reverted.
    ///
    /// Separate from `insert` on purpose. An upsert would silently recreate a
    /// row that something else had removed, and would hide which of the two
    /// actually happened.
    ///
    /// Throws `notFound` when no record carries this id.
    func update(_ assessment: Assessment) async throws

    /// Throws `notFound` when no record carries this id.
    func fetch(id: UUID) async throws -> Assessment

    func fetchAll() async throws -> [Assessment]
}
