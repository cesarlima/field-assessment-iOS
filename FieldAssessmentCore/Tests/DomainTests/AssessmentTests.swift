import XCTest
@testable import Domain

/// Entity rules that no use case can reach, because the use cases stamp the
/// right values by construction. They are the last line of defence, so they
/// get exercised directly.
final class AssessmentTests: XCTestCase {
    private let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
    private let now = Date(timeIntervalSince1970: 1_700_000_900)

    func test_adding_evidenceOwnedByAnotherAssessment_throws() throws {
        let assessment = Assessment(id: UUID(),
                                    title: nil,
                                    notes: nil,
                                    location: nil,
                                    inspector: nil,
                                    evidences: [],
                                    now: createdAt)

        let foreign = Evidence(id: UUID(),
                               assessmentId: UUID(),
                               type: .image,
                               fileName: "whatever.heic",
                               notes: nil,
                               createdAt: createdAt)

        XCTAssertThrowsError(try assessment.adding(foreign, at: now)) { error in
            XCTAssertEqual(error as? AssessmentError, .evidenceBelongsToAnotherAssessment)
        }
    }
}
