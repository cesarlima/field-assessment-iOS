//
//  AssessmentEdit.swift
//  FieldAssessment
//
//  Created by MacPro on 24/08/26.
//

import Foundation

/// A single change to a draft assessment.
///
/// Modelled as a value rather than as optional parameters so that "leave this
/// field alone" and "clear this field" stay distinguishable without the
/// `String??` that a `with(...)` signature would need. Adding a field here is
/// a compile error everywhere it is handled, which is the point.
public enum AssessmentEdit: Sendable, Equatable {
    case title(String?)
    case notes(String?)
    case location(String?)
    case inspector(String?)
}
