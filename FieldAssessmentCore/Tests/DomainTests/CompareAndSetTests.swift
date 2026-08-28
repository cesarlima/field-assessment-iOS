import XCTest
@testable import Domain

final class CompareAndSetTests: XCTestCase {
    private let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
    private let later = Date(timeIntervalSince1970: 1_700_000_900)
    private let assessmentId = UUID()

    private var capture: CapturedFile {
        CapturedFile(id: UUID(),
                     assessmentId: assessmentId,
                     url: URL(fileURLWithPath: "/tmp/capture.mov"))
    }

    private func draft() -> Assessment {
        Assessment(id: assessmentId,
                   title: nil,
                   notes: nil,
                   location: "Warehouse 3",
                   inspector: "Ana",
                   now: createdAt)
    }

    // MARK: - The token

    func test_creation_startsAtVersionOne() {
        XCTAssertEqual(draft().version, 1)
    }

    func test_aChangeCarriesTheVersionItWillBecome() throws {
        let existing = draft()
        let edited = try existing.applying(.notes("cracked beam"), at: later)

        XCTAssertEqual(edited.version, 2)
    }

    func test_aChangeThatChangesNothingDoesNotBumpTheVersion() throws {
        let existing = draft()
        let same = try existing.applying(.location("Warehouse 3"), at: later)

        XCTAssertEqual(same.version, 1, "a redundant autosave must not consume a version")
    }

    // MARK: - The write

    func test_update_withAStaleVersion_throwsAndWritesNothing() async throws {
        let existing = draft()
        let repository = FakeAssessmentRepository(seed: [existing])

        // Someone else writes first, taking the record to version 2.
        let theirs = try existing.applying(.notes("theirs"), at: later)
        try await repository.update(theirs)

        // Ours was computed from version 1 and still expects it.
        let ours = try existing.applying(.title("ours"), at: later)

        await XCTAssertThrowsErrorAsync(try await repository.update(ours)) { error in
            XCTAssertEqual(error as? AssessmentRepositoryError,
                           .staleWrite(id: existing.id, expected: 1, found: 2))
        }

        let stored = try await repository.fetch(id: existing.id)
        XCTAssertEqual(stored.notes, "theirs", "the earlier write must survive")
        XCTAssertNil(stored.title)
    }

    // MARK: - The retry

    func test_addEvidence_retriesWithoutFilingTheMediaTwice() async throws {
        let existing = draft()
        let repository = FakeAssessmentRepository(seed: [existing])
        let files = FakeEvidenceFileStore()
        let later = later

        // A note lands between AddEvidence's read and its write, forcing one
        // collision and one retry.
        let theirs = try existing.applying(.notes("cracked beam"), at: later)
        await repository.onBeforeUpdate { theirs }

        let sut = AddEvidence(repository: repository, files: files, now: { later })
        let result = try await sut.execute(capturing: capture,
                                           type: .video)

        XCTAssertEqual(result.notes, "cracked beam", "the other write survives")
        XCTAssertEqual(result.evidences.count, 1, "and ours still lands")
        XCTAssertEqual(result.version, 3, "two writes, two versions")

        let stored = await files.stored
        XCTAssertEqual(stored.count, 1, "a retry must not move the media again")
    }

    /// `updatedAt` means last local change, so it belongs to the attempt that
    /// wrote — not to the one that collided. A retry stamping its original
    /// time would order the assessment before an edit it already contains.
    func test_addEvidence_retryStampsTheTimeOfTheAttemptThatWrote() async throws {
        let existing = draft()
        let repository = FakeAssessmentRepository(seed: [existing])
        let files = FakeEvidenceFileStore()

        let capturedAt = Date(timeIntervalSince1970: 1_700_000_100)
        let noteAt = Date(timeIntervalSince1970: 1_700_000_200)
        let retriedAt = Date(timeIntervalSince1970: 1_700_000_300)
        let clock = SteppingClock([capturedAt, capturedAt, retriedAt])

        let theirs = try existing.applying(.notes("cracked beam"), at: noteAt)
        await repository.onBeforeUpdate { theirs }

        let sut = AddEvidence(repository: repository, files: files, now: clock.now)
        let result = try await sut.execute(capturing: capture,
                                           type: .video)

        XCTAssertEqual(result.updatedAt, retriedAt)
        XCTAssertGreaterThan(result.updatedAt, theirs.updatedAt,
                             "never older than the write it rebased on")
        XCTAssertEqual(result.evidences.first?.createdAt, capturedAt,
                       "the photo was taken before any of it")
    }

    func test_whenRetriesRunOut_theConflictIsReported() async {
        let existing = draft()
        let repository = FakeAssessmentRepository(seed: [existing])
        await repository.failEveryUpdateAsStale()

        let later = later
        let sut = UpdateAssessment(repository: repository, now: { later })

        await XCTAssertThrowsErrorAsync(try await sut.execute(id: existing.id, .notes("never lands"))) { error in
            guard case .staleWrite? = error as? AssessmentRepositoryError else {
                return XCTFail("expected staleWrite, got \(error)")
            }
        }

        let writes = await repository.writes
        XCTAssertEqual(writes, 0)
    }
}
