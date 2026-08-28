//
//  AssessmentRequirement.swift
//  FieldAssessment
//
//  Created by MacPro on 26/08/26.
//

import Foundation

/// Something R4 asks for before an inspection can be declared finished.
///
/// Not persisted, so it carries no raw value — the convention about `String`
/// raw values exists to keep stored data readable across a reordering, and
/// nothing here is stored.
public enum AssessmentRequirement: Sendable, Equatable {
    case location
    case inspector
    case evidence
}
