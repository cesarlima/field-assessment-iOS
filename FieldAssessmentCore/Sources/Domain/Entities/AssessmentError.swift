//
//  AssessmentError.swift
//  FieldAssessment
//
//  Created by MacPro on 24/08/26.
//

import Foundation

public enum AssessmentError: Error, Equatable, Sendable {
    /// R6: a completed assessment is a submitted record. It is not reopened
    /// and it is not edited.
    case alreadyCompleted

    /// Evidence belongs to exactly one assessment and is never shared between
    /// them. Attaching a piece stamped with another assessment's id would
    /// leave a row whose parent disagrees with where it is filed.
    case evidenceBelongsToAnotherAssessment

    /// R4 is not met yet. Carries everything that is missing, because R5 says
    /// the inspector sees all of it at once rather than one failed attempt at
    /// a time.
    case incomplete([AssessmentRequirement])
}
