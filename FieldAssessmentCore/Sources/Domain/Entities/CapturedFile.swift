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
    public let url: URL

    public init(url: URL) {
        self.url = url
    }
}
