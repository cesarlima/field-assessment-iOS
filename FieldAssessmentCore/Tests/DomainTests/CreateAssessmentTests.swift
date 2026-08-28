import XCTest
@testable import Domain

final class CreateAssessmentTests: XCTestCase {
    private let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)

    /// Minted when the screen opens, held by the caller, reused by every
    /// attempt at the same creation. The capture carries it too, which is how
    /// the capture path names its assessment.
    private let id = UUID()
    private let captureId = UUID()

    private var capture: CapturedFile {
        CapturedFile(id: captureId,
                     assessmentId: id,
                     url: URL(fileURLWithPath: "/tmp/capture.mov"))
    }

    private func makeSUT(
        fileStoreFailure: Error? = nil
    ) -> (CreateAssessment, FakeAssessmentRepository, FakeEvidenceFileStore) {
        let repository = FakeAssessmentRepository()
        let files = FakeEvidenceFileStore(failure: fileStoreFailure)
        let now = fixedNow
        let sut = CreateAssessment(repository: repository, files: files, now: { now })
        return (sut, repository, files)
    }

    // MARK: - First input is text

    func test_execute_withText_storesAnOpenAssessment() async throws {
        let (sut, repository, _) = makeSUT()

        let assessment = try await sut.execute(id: id, location: "Warehouse 3")

        XCTAssertEqual(assessment.status, .open)
        XCTAssertEqual(assessment.location, "Warehouse 3")
        XCTAssertEqual(assessment.createdAt, fixedNow)
        XCTAssertEqual(assessment.updatedAt, fixedNow)
        XCTAssertTrue(assessment.evidences.isEmpty)

        let saved = await repository.inserted
        XCTAssertEqual(saved, [assessment])
    }

    func test_execute_withText_trimsWhitespace() async throws {
        let (sut, _, _) = makeSUT()

        let assessment = try await sut.execute(id: id, inspector: "  Ana  ")

        XCTAssertEqual(assessment.inspector, "Ana")
    }

    func test_execute_withNoInput_storesNothing() async {
        let (sut, repository, _) = makeSUT()

        await XCTAssertThrowsErrorAsync(try await sut.execute(id: id)) { error in
            XCTAssertEqual(error as? CreateAssessmentError, .noInput)
        }

        let saved = await repository.inserted
        XCTAssertTrue(saved.isEmpty)
    }

    func test_execute_withWhitespaceOnly_storesNothing() async {
        let (sut, repository, _) = makeSUT()

        await XCTAssertThrowsErrorAsync(try await sut.execute(id: id, title: "   ", notes: "\n")) { error in
            XCTAssertEqual(error as? CreateAssessmentError, .noInput)
        }

        let saved = await repository.inserted
        XCTAssertTrue(saved.isEmpty)
    }

    // MARK: - First input is a capture

    func test_execute_withCapture_storesAssessmentAndEvidenceTogether() async throws {
        let (sut, repository, _) = makeSUT()

        let assessment = try await sut.execute(capturing: capture, type: .video)

        XCTAssertEqual(assessment.status, .open)
        XCTAssertEqual(assessment.evidences.count, 1)

        let evidence = try XCTUnwrap(assessment.evidences.first)
        XCTAssertEqual(evidence.assessmentId, assessment.id)
        XCTAssertEqual(evidence.type, .video)
        XCTAssertEqual(evidence.createdAt, fixedNow)

        // One save call: the record and its first evidence land in one write.
        let saved = await repository.inserted
        XCTAssertEqual(saved, [assessment])
    }

    func test_execute_withCapture_namesTheFileAfterTheEvidence() async throws {
        let (sut, _, files) = makeSUT()

        let assessment = try await sut.execute(capturing: capture, type: .video)
        let evidence = try XCTUnwrap(assessment.evidences.first)

        XCTAssertEqual(evidence.fileName, "\(evidence.id.uuidString).mov")

        let stored = await files.stored
        XCTAssertEqual(stored, [evidence.id])
    }

    func test_execute_withCapture_whenFilingTheFileFails_storesNothing() async {
        let (sut, repository, _) = makeSUT(fileStoreFailure: FakeError.diskFull)

        await XCTAssertThrowsErrorAsync(try await sut.execute(capturing: capture, type: .image)) { error in
            XCTAssertEqual(error as? FakeError, .diskFull)
        }

        // The row must never exist without the file it points at.
        let saved = await repository.inserted
        XCTAssertTrue(saved.isEmpty)
    }

    // MARK: - The same creation running twice

    /// Two calls with the same capture, no error and nothing lost in between:
    /// the button tapped twice. Before the caller owned the id, this wrote two
    /// assessments carrying one evidence id and one file, so deleting either
    /// took the other's photo.
    func test_execute_withCapture_twiceInParallel_writesOneAssessment() async throws {
        let (sut, repository, files) = makeSUT()
        let capture = self.capture

        async let first = sut.execute(capturing: capture, type: .image)
        async let second = sut.execute(capturing: capture, type: .image)
        let (a, b) = try await (first, second)

        XCTAssertEqual(a.id, b.id)
        XCTAssertEqual(a, b, "both callers see the record that exists")

        let inserted = await repository.inserted
        XCTAssertEqual(inserted.count, 1)

        let stored = await files.stored
        XCTAssertEqual(stored, [capture.id], "and the media was filed once")
    }

    /// The same shape on the text path: a blur flush and a background flush
    /// firing together used to leave two drafts behind.
    func test_execute_withText_twiceInParallel_writesOneAssessment() async throws {
        let (sut, repository, _) = makeSUT()
        let id = self.id

        async let first = sut.execute(id: id, location: "Warehouse 3")
        async let second = sut.execute(id: id, location: "Warehouse 3")
        _ = try await (first, second)

        let inserted = await repository.inserted
        XCTAssertEqual(inserted.count, 1)
    }

    /// A repeat is reported as success, and it lands on the record that
    /// exists rather than writing a second one.
    func test_execute_whenTheIdIsAlreadyTaken_writesOneRecord() async throws {
        let (sut, repository, _) = makeSUT()

        let created = try await sut.execute(id: id, location: "Warehouse 3")
        let again = try await sut.execute(id: id, location: "Warehouse 3")

        XCTAssertEqual(again, created, "a repeat carrying the same text changes nothing")

        let inserted = await repository.inserted
        XCTAssertEqual(inserted.count, 1)
    }

    /// R7 closes the window at two moments, and leaving the screen hits both:
    /// the blur flush and the background flush go out together. Whichever
    /// loses the primary key is the one holding the fuller text, half the
    /// time.
    ///
    /// Returning the stored record would drop what it was carrying. The
    /// argument that the screen still holds it and flushes again does not
    /// apply here — the app is suspending, so there is no next flush.
    func test_execute_whenTheIdIsAlreadyTaken_mergesWhatThisCallCarried() async throws {
        let (sut, repository, _) = makeSUT()

        _ = try await sut.execute(id: id, title: "Bay 4")
        let result = try await sut.execute(id: id, title: "Bay 4", notes: "cracked beam")

        XCTAssertEqual(result.title, "Bay 4")
        XCTAssertEqual(result.notes, "cracked beam", "the note must not be dropped")

        let stored = try await repository.fetch(id: id)
        XCTAssertEqual(stored.notes, "cracked beam", "durably")
    }

    /// A field this call says nothing about is left alone. `nil` means not
    /// provided, not cleared — clearing is an explicit edit on
    /// `UpdateAssessment`.
    func test_execute_whenTheIdIsAlreadyTaken_leavesFieldsItSaysNothingAboutAlone() async throws {
        let (sut, _, _) = makeSUT()

        _ = try await sut.execute(id: id, title: "Bay 4", inspector: "Ana")
        let result = try await sut.execute(id: id, notes: "cracked beam")

        XCTAssertEqual(result.title, "Bay 4")
        XCTAssertEqual(result.inspector, "Ana")
        XCTAssertEqual(result.notes, "cracked beam")
    }

    /// The capture names the assessment it was taken for, so the record built
    /// from it cannot end up under a different id. There is no separate
    /// parameter to disagree with.
    func test_execute_withCapture_takesTheAssessmentIdFromTheCapture() async throws {
        let (sut, _, _) = makeSUT()

        let assessment = try await sut.execute(capturing: capture, type: .image)

        XCTAssertEqual(assessment.id, capture.assessmentId)
        XCTAssertEqual(assessment.evidences.first?.assessmentId, capture.assessmentId)
    }

    /// R16's own example: the screen mints one id, then a debounced text flush
    /// and a capture race on it. The text create wins the primary key.
    ///
    /// By this point `store` has already moved the capture out of temporary
    /// storage, so the screen is not holding the photo any more. Returning the
    /// text-only record would report success with the file on disk and no row
    /// naming it — an orphan the launch sweep deletes. The capture has to be
    /// attached to the record that won.
    func test_execute_withCapture_whenAnotherCreateWonTheId_attachesTheEvidence() async throws {
        let (sut, repository, files) = makeSUT()

        _ = try await sut.execute(id: id, location: "Warehouse 3")
        let result = try await sut.execute(capturing: capture, type: .image)

        XCTAssertEqual(result.location, "Warehouse 3", "the record that won is kept")
        XCTAssertEqual(result.evidences.count, 1, "and the photo is attached, not dropped")
        XCTAssertEqual(result.evidences.first?.id, capture.id)

        let stored = try await repository.fetch(id: id)
        XCTAssertEqual(stored.evidences.count, 1, "durably, not only in the value returned")

        let removed = await files.removed
        XCTAssertTrue(removed.isEmpty)
    }

    /// The capture that lost the race must keep its file: the record that won
    /// points at it.
    func test_execute_withCapture_whenTheIdIsAlreadyTaken_keepsTheMedia() async throws {
        let (sut, _, files) = makeSUT()

        _ = try await sut.execute(capturing: capture, type: .image)
        _ = try await sut.execute(capturing: capture, type: .image)

        let removed = await files.removed
        XCTAssertTrue(removed.isEmpty)

        let stored = await files.stored
        XCTAssertEqual(stored, [capture.id])
    }
}
