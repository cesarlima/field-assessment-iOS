import XCTest
@testable import Domain

final class AddEvidenceTests: XCTestCase {
    private let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
    private let capturedAt = Date(timeIntervalSince1970: 1_700_000_900)
    private let capture = CapturedFile(url: URL(fileURLWithPath: "/tmp/capture.mov"))

    private func draft() -> Assessment {
        Assessment(id: UUID(),
                   title: nil,
                   notes: nil,
                   location: "Warehouse 3",
                   inspector: "Ana",
                   evidences: [],
                   now: createdAt)
    }

    private func completed() -> Assessment {
        Assessment(reconstituting: UUID(),
                   title: nil,
                   notes: nil,
                   location: "Warehouse 3",
                   createdAt: createdAt,
                   updatedAt: createdAt,
                   inspector: "Ana",
                   status: .completed,
                   evidences: [])
    }

    private func makeSUT(
        seed: [Assessment],
        fileStoreFailure: Error? = nil
    ) -> (AddEvidence, FakeAssessmentRepository, FakeEvidenceFileStore) {
        let repository = FakeAssessmentRepository(seed: seed)
        let files = FakeEvidenceFileStore(failure: fileStoreFailure)
        let capturedAt = capturedAt
        let sut = AddEvidence(repository: repository, files: files, now: { capturedAt })
        return (sut, repository, files)
    }

    // MARK: - Attaching

    func test_execute_appendsEvidenceAndMovesUpdatedAt() async throws {
        let existing = draft()
        let (sut, repository, _) = makeSUT(seed: [existing])

        let result = try await sut.execute(assessmentId: existing.id,
                                           capturing: capture,
                                           type: .video)

        XCTAssertEqual(result.evidences.count, 1)
        XCTAssertEqual(result.updatedAt, capturedAt)
        XCTAssertEqual(result.createdAt, createdAt)

        let evidence = try XCTUnwrap(result.evidences.first)
        XCTAssertEqual(evidence.assessmentId, existing.id)
        XCTAssertEqual(evidence.type, .video)
        XCTAssertEqual(evidence.fileName, "\(evidence.id.uuidString).mov")

        let updated = await repository.updated
        XCTAssertEqual(updated, [result])
    }

    func test_execute_keepsExistingEvidence() async throws {
        let existing = draft()
        let (sut, _, _) = makeSUT(seed: [existing])

        let first = try await sut.execute(assessmentId: existing.id, capturing: capture, type: .image)
        let second = try await sut.execute(assessmentId: existing.id, capturing: capture, type: .audio)

        XCTAssertEqual(second.evidences.count, 2)
        XCTAssertEqual(second.evidences.map(\.type), [.image, .audio])
        XCTAssertEqual(second.evidences.first, first.evidences.first)
    }

    func test_execute_trimsEvidenceNotes() async throws {
        let existing = draft()
        let (sut, _, _) = makeSUT(seed: [existing])

        let result = try await sut.execute(assessmentId: existing.id,
                                           capturing: capture,
                                           type: .image,
                                           evidenceNotes: "  cracked beam  ")

        XCTAssertEqual(result.evidences.first?.notes, "cracked beam")
    }

    // MARK: - Refusals

    func test_execute_whenFilingTheFileFails_writesNothing() async {
        let existing = draft()
        let (sut, repository, _) = makeSUT(seed: [existing], fileStoreFailure: FakeError.diskFull)

        await XCTAssertThrowsErrorAsync(
            try await sut.execute(assessmentId: existing.id, capturing: capture, type: .image)
        ) { error in
            XCTAssertEqual(error as? FakeError, .diskFull)
        }

        let writes = await repository.writes
        XCTAssertEqual(writes, 0)
    }

    func test_execute_onCompletedAssessment_refusesBeforeMovingTheFile() async {
        let existing = completed()
        let (sut, repository, files) = makeSUT(seed: [existing])

        await XCTAssertThrowsErrorAsync(
            try await sut.execute(assessmentId: existing.id, capturing: capture, type: .image)
        ) { error in
            XCTAssertEqual(error as? AssessmentError, .alreadyCompleted)
        }

        // No file was filed, so the refusal leaves no orphan behind.
        let stored = await files.stored
        XCTAssertTrue(stored.isEmpty)

        let writes = await repository.writes
        XCTAssertEqual(writes, 0)
    }

    func test_execute_withUnknownId_throwsNotFound() async {
        let (sut, _, files) = makeSUT(seed: [])
        let missing = UUID()

        await XCTAssertThrowsErrorAsync(
            try await sut.execute(assessmentId: missing, capturing: capture, type: .image)
        ) { error in
            XCTAssertEqual(error as? AssessmentRepositoryError, .notFound(missing))
        }

        let stored = await files.stored
        XCTAssertTrue(stored.isEmpty)
    }
}
