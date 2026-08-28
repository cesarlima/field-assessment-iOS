//
//  CapturedFile.swift
//  FieldAssessment
//
//  Created by MacPro on 24/08/26.
//

import Foundation

/// A file the app already owns, sitting in temporary storage, waiting to be
/// filed as evidence.
///
/// Whoever builds one guarantees the URL is a plain local file this app may
/// move: not a security-scoped reference from the photo picker or the Files
/// app, and not a remote URL. Copy out of the picker's sandbox first.
public struct CapturedFile: Sendable, Equatable {
    /// Identity of this capture, minted when the file is captured and kept by
    /// the caller until the write lands.
    ///
    /// Filing the file moves it, so the source is gone after the first
    /// attempt. This id is what makes a second attempt the *same* attempt: the
    /// destination is derived from it, so a retry finds the file the first
    /// attempt already moved instead of looking for a source that no longer
    /// exists. The evidence row takes this id too, so the row and the file on
    /// disk carry the same name.
    public let id: UUID

    /// The assessment this capture was taken for, decided when the shutter
    /// fires and never afterwards.
    ///
    /// It is carried here rather than passed alongside because a capture
    /// belongs to exactly one assessment, and two ways to say which one is one
    /// too many: the same capture aimed at a second assessment would give two
    /// records a row with the same evidence id naming the same file, and
    /// deleting either would take the other's photo. With a single source
    /// there is nothing to disagree with.
    public let assessmentId: UUID

    public let url: URL

    public init(id: UUID, assessmentId: UUID, url: URL) {
        self.id = id
        self.assessmentId = assessmentId
        self.url = url
    }
}
