import XCTest
@testable import Domain

/// A use case reads the assessment, awaits, then writes the whole aggregate
/// back. Anything committed inside that window is overwritten by the snapshot
/// taken before it.
///
/// The second writer here is not another device — decision 13 rules that out.
/// It is the app itself: R7's debounced autosave firing while a capture is
/// being filed, or a capture landing while an edit is in flight.
final class ConcurrentWriteTests: XCTestCase {
    private let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
    private let later = Date(timeIntervalSince1970: 1_700_000_900)
    private let capture = CapturedFile(url: URL(fileURLWithPath: "/tmp/capture.mov"))

    private func draft(id: UUID = UUID()) -> Assessment {
        Assessment(id: id,
                   title: nil,
                   notes: nil,
                   location: "Warehouse 3",
                   inspector: "Ana",
                   now: createdAt)
    }

    // MARK: - AddEvidence holds the widest window: the media move

    func test_addEvidence_keepsANoteFlushedWhileTheMediaWasBeingFiled() async throws {
        let existing = draft()
        let repository = FakeAssessmentRepository(seed: [existing])
        let files = FakeEvidenceFileStore()
        let later = later

        let update = UpdateAssessment(repository: repository, now: { later })
        let addEvidence = AddEvidence(repository: repository, files: files, now: { later })

        // The inspector typed a note; the debounce timer fires while the video
        // is still being filed.
        await files.onStore {
            _ = try? await update.execute(id: existing.id, .notes("cracked beam"))
        }

        let result = try await addEvidence.execute(assessmentId: existing.id,
                                                   capturing: capture,
                                                   type: .video)

        XCTAssertEqual(result.evidences.count, 1, "the capture must be attached")
        XCTAssertEqual(result.notes, "cracked beam", "the note must survive the capture")

        let stored = try await repository.fetch(id: existing.id)
        XCTAssertEqual(stored.notes, "cracked beam")
        XCTAssertEqual(stored.evidences.count, 1)
    }

    func test_addEvidence_doesNotReopenACompletionThatLandedDuringTheCapture() async {
        let existing = draft()
        let repository = FakeAssessmentRepository(seed: [existing])
        let files = FakeEvidenceFileStore()
        let later = later

        let completed = Assessment(reconstituting: existing.id,
                                   version: 2,
                                   title: nil,
                                   notes: nil,
                                   location: "Warehouse 3",
                                   createdAt: createdAt,
                                   updatedAt: later,
                                   inspector: "Ana",
                                   status: .completed,
                                   evidences: [])

        // Completion lands while the media is being filed.
        await files.onStore {
            await repository.overwrite(completed)
        }

        let addEvidence = AddEvidence(repository: repository, files: files, now: { later })
        _ = try? await addEvidence.execute(assessmentId: existing.id,
                                           capturing: capture,
                                           type: .video)

        let stored = try? await repository.fetch(id: existing.id)
        XCTAssertEqual(stored?.status, .completed,
                       "a completed assessment must not be rolled back to open (R6)")
    }

    // MARK: - UpdateAssessment holds a shorter window, same shape

    func test_updateAssessment_keepsEvidenceAttachedWhileTheEditWasInFlight() async throws {
        let existing = draft()
        let repository = FakeAssessmentRepository(seed: [existing])
        let later = later

        let evidence = Evidence(id: UUID(),
                                assessmentId: existing.id,
                                type: .image,
                                fileName: "photo.heic",
                                notes: nil,
                                createdAt: later)
        let withEvidence = try existing.adding(evidence, at: later)

        // A capture completes between this use case's read and its write.
        await repository.onBeforeUpdate { withEvidence }

        let update = UpdateAssessment(repository: repository, now: { later })
        let result = try await update.execute(id: existing.id, .notes("cracked beam"))

        XCTAssertEqual(result.notes, "cracked beam")
        XCTAssertEqual(result.evidences.count, 1, "the capture must not be dropped")

        let stored = try await repository.fetch(id: existing.id)
        XCTAssertEqual(stored.evidences.count, 1)
    }
}
