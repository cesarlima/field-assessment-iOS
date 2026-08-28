import XCTest
@testable import Domain

final class CompleteAssessmentTests: XCTestCase {
    private let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
    private let completedAt = Date(timeIntervalSince1970: 1_700_000_900)

    private func evidence(of id: UUID) -> Evidence {
        Evidence(id: UUID(),
                 assessmentId: id,
                 type: .image,
                 fileName: "beam.heic",
                 notes: nil,
                 createdAt: createdAt)
    }

    private func assessment(id: UUID = UUID(),
                            location: String? = "Warehouse 3",
                            inspector: String? = "Ana",
                            withEvidence: Bool = true,
                            status: AssessmentStatus = .open) -> Assessment {
        Assessment(reconstituting: id,
                   version: 1,
                   title: nil,
                   notes: nil,
                   location: location,
                   createdAt: createdAt,
                   updatedAt: createdAt,
                   inspector: inspector,
                   status: status,
                   evidences: withEvidence ? [evidence(of: id)] : [])
    }

    private func makeSUT(seed: [Assessment]) -> (CompleteAssessment, FakeAssessmentRepository) {
        let repository = FakeAssessmentRepository(seed: seed)
        let completedAt = completedAt
        return (CompleteAssessment(repository: repository, now: { completedAt }), repository)
    }

    // MARK: - What is missing

    /// R5: everything at once, not one failed attempt at a time.
    func test_execute_onAnEmptyDraft_reportsEveryRequirement() async {
        let existing = assessment(location: nil, inspector: nil, withEvidence: false)
        let (sut, repository) = makeSUT(seed: [existing])

        await XCTAssertThrowsErrorAsync(try await sut.execute(id: existing.id)) { error in
            XCTAssertEqual(error as? AssessmentError,
                           .incomplete([.location, .inspector, .evidence]))
        }

        let writes = await repository.writes
        XCTAssertEqual(writes, 0, "a refusal writes nothing")
    }

    func test_execute_whenOnlyEvidenceIsMissing_reportsOnlyEvidence() async {
        let existing = assessment(withEvidence: false)
        let (sut, _) = makeSUT(seed: [existing])

        await XCTAssertThrowsErrorAsync(try await sut.execute(id: existing.id)) { error in
            XCTAssertEqual(error as? AssessmentError, .incomplete([.evidence]))
        }
    }

    /// The screen needs this before the tap, to show what is still open while
    /// the inspector fills the form.
    func test_missingForCompletion_isEmptyWhenEverythingIsThere() {
        XCTAssertTrue(assessment().missingForCompletion.isEmpty)
    }

    // MARK: - Completing

    func test_execute_marksTheAssessmentCompleted() async throws {
        let existing = assessment()
        let (sut, repository) = makeSUT(seed: [existing])

        let result = try await sut.execute(id: existing.id)

        XCTAssertEqual(result.status, .completed)
        XCTAssertEqual(result.version, 2)
        XCTAssertEqual(result.updatedAt, completedAt)
        XCTAssertEqual(result.createdAt, createdAt)
        XCTAssertEqual(result.evidences, existing.evidences)

        let updated = await repository.updated
        XCTAssertEqual(updated, [result])
    }

    /// A second tap on Finish asks for nothing the first did not already do.
    func test_execute_onACompletedAssessment_writesNothing() async throws {
        let existing = assessment(status: .completed)
        let (sut, repository) = makeSUT(seed: [existing])

        let result = try await sut.execute(id: existing.id)

        XCTAssertEqual(result, existing)

        let writes = await repository.writes
        XCTAssertEqual(writes, 0)
    }

    func test_execute_withUnknownId_throwsNotFound() async {
        let (sut, _) = makeSUT(seed: [])
        let missing = UUID()

        await XCTAssertThrowsErrorAsync(try await sut.execute(id: missing)) { error in
            XCTAssertEqual(error as? AssessmentRepositoryError, .notFound(missing))
        }
    }

    // MARK: - The window

    /// Validation runs on every attempt, against what was just read. An
    /// autosave clearing the location while the completion is in flight has to
    /// stop it — otherwise a record that no longer meets R4 is submitted, and
    /// R6 says nothing reopens it afterwards.
    func test_execute_whenARequirementIsLostDuringTheWrite_refusesOnTheRetry() async {
        let existing = assessment()
        let repository = FakeAssessmentRepository(seed: [existing])
        let completedAt = completedAt

        let cleared = try? existing.applying(.location(nil), at: completedAt)
        await repository.onBeforeUpdate { cleared }

        let sut = CompleteAssessment(repository: repository, now: { completedAt })

        await XCTAssertThrowsErrorAsync(try await sut.execute(id: existing.id)) { error in
            XCTAssertEqual(error as? AssessmentError, .incomplete([.location]))
        }

        let stored = try? await repository.fetch(id: existing.id)
        XCTAssertEqual(stored?.status, .open, "nothing was submitted")
    }
}
