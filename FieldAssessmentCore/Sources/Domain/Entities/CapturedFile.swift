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
    /// It is carried here rather than passed alongside so that one place says
    /// it. With the assessment arriving as a separate parameter, the same
    /// value was stamped on the evidence and used for the commit, so
    /// `adding`'s ownership guard could never fire from a use case; and the
    /// question the refusal path has to answer — is anything pointing at this
    /// file — needed a flag from `store` to answer. One source removes both.
    ///
    /// This is not defending against a capture reaching two assessments. The
    /// creation screen holds one assessment id and nothing carries a capture
    /// to another screen, so that sequence has no path through the app
    /// (decision 24).
    public let assessmentId: UUID

    public let url: URL

    public init(id: UUID, assessmentId: UUID, url: URL) {
        self.id = id
        self.assessmentId = assessmentId
        self.url = url
    }
}
