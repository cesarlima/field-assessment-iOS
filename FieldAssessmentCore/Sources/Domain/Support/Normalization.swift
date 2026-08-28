//
//  Normalization.swift
//  FieldAssessment
//
//  Created by MacPro on 24/08/26.
//

import Foundation

/// Trimmed, or nil when nothing but whitespace is left.
///
/// Shared by creation and editing so both agree on what counts as a real
/// input. A typed space is not one.
func normalized(_ value: String?) -> String? {
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
          !trimmed.isEmpty else { return nil }
    return trimmed
}
