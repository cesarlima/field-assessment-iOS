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
}

public protocol AssessmentRepository: Sendable {
    /// Writes a new assessment and everything it carries in one transaction.
    ///
    /// Creating a record and recording its first evidence is a single write:
    /// an app terminated between two of them would leave the empty assessment
    /// R8 forbids.
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
