import XCTest
@testable import Domain

final class AddEvidenceTests: XCTestCase {
    private let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
    private let capturedAt = Date(timeIntervalSince1970: 1_700_000_900)
    private let capture = CapturedFile(id: UUID(), url: URL(fileURLWithPath: "/tmp/capture.mov"))

    private func draft() -> Assessment {
        Assessment(id: UUID(),
                   title: nil,
                   notes: nil,
                   location: "Warehouse 3",
                   inspector: "Ana",
                   now: createdAt)
    }

    private func completed() -> Assessment {
        Assessment(reconstituting: UUID(),
                   version: 1,
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
        let secondCapture = CapturedFile(id: UUID(),
                                         url: URL(fileURLWithPath: "/tmp/second.m4a"))

        let first = try await sut.execute(assessmentId: existing.id, capturing: capture, type: .image)
        let second = try await sut.execute(assessmentId: existing.id, capturing: secondCapture, type: .audio)

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

    // MARK: - Retrying the same capture

    /// Filing the media moves it, so the source is gone the moment the first
    /// attempt gets past `store`. The capture's id is what makes the second
    /// call continue the first one instead of starting a new, impossible one.
    func test_execute_afterAFailedWrite_retryAdoptsTheMediaAlreadyFiled() async throws {
        let existing = draft()
        let (sut, repository, files) = makeSUT(seed: [existing])
        await repository.failNextUpdate(with: FakeError.diskFull)

        await XCTAssertThrowsErrorAsync(
            try await sut.execute(assessmentId: existing.id, capturing: capture, type: .video)
        ) { error in
            XCTAssertEqual(error as? FakeError, .diskFull)
        }

        // The media survived the failure: deleting it would have destroyed the
        // only copy left of the capture.
        let afterFailure = await files.stored
        XCTAssertEqual(afterFailure, [capture.id])
        let removed = await files.removed
        XCTAssertTrue(removed.isEmpty)

        let result = try await sut.execute(assessmentId: existing.id,
                                           capturing: capture,
                                           type: .video)

        XCTAssertEqual(result.evidences.count, 1, "the retry must attach the capture")
        XCTAssertEqual(result.evidences.first?.id, capture.id)

        let stored = await files.stored
        XCTAssertEqual(stored, [capture.id], "and must not move any media a second time")
    }

    /// The same file with a fresh id is a different capture, and there is
    /// nothing left to move. This is what the first attempt used to do on
    /// every retry, and why it could never succeed.
    func test_execute_retryingWithANewIdFindsNothingToFile() async throws {
        let existing = draft()
        let (sut, repository, _) = makeSUT(seed: [existing])
        await repository.failNextUpdate(with: FakeError.diskFull)

        _ = try? await sut.execute(assessmentId: existing.id, capturing: capture, type: .video)

        let sameFileNewId = CapturedFile(id: UUID(), url: capture.url)
        await XCTAssertThrowsErrorAsync(
            try await sut.execute(assessmentId: existing.id, capturing: sameFileNewId, type: .video)
        ) { error in
            XCTAssertEqual(error as? FakeError, .sourceIsGone)
        }
    }

    /// At-least-once delivery: a caller that retries a capture which actually
    /// landed must not end up with two of it.
    func test_execute_twiceWithTheSameCapture_attachesItOnce() async throws {
        let existing = draft()
        let (sut, _, _) = makeSUT(seed: [existing])

        _ = try await sut.execute(assessmentId: existing.id, capturing: capture, type: .video)
        let result = try await sut.execute(assessmentId: existing.id, capturing: capture, type: .video)

        XCTAssertEqual(result.evidences.count, 1)
    }

    // MARK: - Refusals

    /// A completion landing while the media is being filed is a refusal, not a
    /// failure: the capture will never be attached, so nothing will ever point
    /// at the file. Leaving it would leak an orphan nobody can explain.
    func test_execute_whenCompletionLandsDuringTheCapture_removesTheFileItFiled() async {
        let existing = draft()
        let (sut, repository, files) = makeSUT(seed: [existing])

        let completed = Assessment(reconstituting: existing.id,
                                   version: 2,
                                   title: nil,
                                   notes: nil,
                                   location: "Warehouse 3",
                                   createdAt: createdAt,
                                   updatedAt: capturedAt,
                                   inspector: "Ana",
                                   status: .completed,
                                   evidences: [])

        await files.onStore {
            await repository.overwrite(completed)
        }

        await XCTAssertThrowsErrorAsync(
            try await sut.execute(assessmentId: existing.id, capturing: capture, type: .video)
        ) { error in
            XCTAssertEqual(error as? AssessmentError, .alreadyCompleted)
        }

        let removed = await files.removed
        XCTAssertEqual(removed, [capture.id])

        let stored = await files.stored
        XCTAssertTrue(stored.isEmpty, "no orphan is left behind")
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
