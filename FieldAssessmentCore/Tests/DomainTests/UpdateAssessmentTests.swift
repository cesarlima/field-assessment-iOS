import XCTest
@testable import Domain

final class UpdateAssessmentTests: XCTestCase {
    private let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
    private let editedAt = Date(timeIntervalSince1970: 1_700_000_900)

    private func draft(location: String? = nil, inspector: String? = nil) -> Assessment {
        Assessment(id: UUID(),
                   title: nil,
                   notes: nil,
                   location: location,
                   inspector: inspector,
                   now: createdAt)
    }

    private func completed(notes: String? = nil) -> Assessment {
        Assessment(reconstituting: UUID(),
                   version: 1,
                   title: nil,
                   notes: notes,
                   location: "Warehouse 3",
                   createdAt: createdAt,
                   updatedAt: createdAt,
                   inspector: "Ana",
                   status: .completed,
                   evidences: [])
    }

    private func makeSUT(seed: [Assessment]) -> (UpdateAssessment, FakeAssessmentRepository) {
        let repository = FakeAssessmentRepository(seed: seed)
        let editedAt = editedAt
        return (UpdateAssessment(repository: repository, now: { editedAt }), repository)
    }

    // MARK: - Applying an edit

    func test_execute_appliesTheEditAndMovesUpdatedAt() async throws {
        let existing = draft()
        let (sut, repository) = makeSUT(seed: [existing])

        let result = try await sut.execute(id: existing.id, .location("Warehouse 3"))

        XCTAssertEqual(result.location, "Warehouse 3")
        XCTAssertEqual(result.updatedAt, editedAt)
        XCTAssertEqual(result.createdAt, createdAt, "createdAt never moves")

        let updated = await repository.updated
        XCTAssertEqual(updated, [result])
    }

    func test_execute_trimsWhitespace() async throws {
        let existing = draft()
        let (sut, _) = makeSUT(seed: [existing])

        let result = try await sut.execute(id: existing.id, .inspector("  Ana  "))

        XCTAssertEqual(result.inspector, "Ana")
    }

    func test_execute_withWhitespaceOnly_clearsTheField() async throws {
        let existing = draft(inspector: "Ana")
        let (sut, _) = makeSUT(seed: [existing])

        let result = try await sut.execute(id: existing.id, .inspector("   "))

        XCTAssertNil(result.inspector)
    }

    func test_execute_appliesSeveralEditsAsOneWrite() async throws {
        let existing = draft()
        let (sut, repository) = makeSUT(seed: [existing])

        let result = try await sut.execute(id: existing.id, [
            .location("Warehouse 3"),
            .inspector("Ana"),
            .notes("Cracked beam")
        ])

        XCTAssertEqual(result.location, "Warehouse 3")
        XCTAssertEqual(result.inspector, "Ana")
        XCTAssertEqual(result.notes, "Cracked beam")

        let writes = await repository.writes
        XCTAssertEqual(writes, 1)
    }

    // MARK: - Nothing changed

    func test_execute_withRedundantEdit_writesNothing() async throws {
        let existing = draft(location: "Warehouse 3")
        let (sut, repository) = makeSUT(seed: [existing])

        let result = try await sut.execute(id: existing.id, .location("Warehouse 3"))

        XCTAssertEqual(result.updatedAt, createdAt, "updatedAt means last change, not last keystroke")

        let writes = await repository.writes
        XCTAssertEqual(writes, 0)
    }

    // MARK: - Refusals

    func test_execute_onCompletedAssessment_throwsAndWritesNothing() async {
        let existing = completed()
        let (sut, repository) = makeSUT(seed: [existing])

        await XCTAssertThrowsErrorAsync(try await sut.execute(id: existing.id, .notes("late change"))) { error in
            XCTAssertEqual(error as? AssessmentError, .alreadyCompleted)
        }

        let writes = await repository.writes
        XCTAssertEqual(writes, 0)
    }

    /// R7's own sequence: the tap on Finish resigns the field's focus, so the
    /// blur flush and the completion both go out. The debounce had already
    /// saved that exact text, so the flush asks for nothing. A write that
    /// changes nothing is a repeat, not an edit, and R6 has no reason to
    /// refuse it — `adding` and `completing` already order it this way.
    func test_execute_withRedundantEditAfterCompletion_writesNothingAndDoesNotThrow() async throws {
        let existing = completed(notes: "cracked beam")
        let (sut, repository) = makeSUT(seed: [existing])

        let result = try await sut.execute(id: existing.id, .notes("cracked beam"))

        XCTAssertEqual(result, existing)

        let writes = await repository.writes
        XCTAssertEqual(writes, 0)
    }

    func test_execute_withUnknownId_throwsNotFound() async {
        let (sut, _) = makeSUT(seed: [])
        let missing = UUID()

        await XCTAssertThrowsErrorAsync(try await sut.execute(id: missing, .notes("anything"))) { error in
            XCTAssertEqual(error as? AssessmentRepositoryError, .notFound(missing))
        }
    }
}
