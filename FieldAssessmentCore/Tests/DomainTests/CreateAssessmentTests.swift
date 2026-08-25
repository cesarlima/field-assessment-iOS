import XCTest
@testable import Domain

final class CreateAssessmentTests: XCTestCase {
    private let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)
    private let capture = CapturedFile(id: UUID(), url: URL(fileURLWithPath: "/tmp/capture.mov"))

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

        let assessment = try await sut.execute(location: "Warehouse 3")

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

        let assessment = try await sut.execute(inspector: "  Ana  ")

        XCTAssertEqual(assessment.inspector, "Ana")
    }

    func test_execute_withNoInput_storesNothing() async {
        let (sut, repository, _) = makeSUT()

        await XCTAssertThrowsErrorAsync(try await sut.execute()) { error in
            XCTAssertEqual(error as? CreateAssessmentError, .noInput)
        }

        let saved = await repository.inserted
        XCTAssertTrue(saved.isEmpty)
    }

    func test_execute_withWhitespaceOnly_storesNothing() async {
        let (sut, repository, _) = makeSUT()

        await XCTAssertThrowsErrorAsync(try await sut.execute(title: "   ", notes: "\n")) { error in
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

    func test_execute_generatesADistinctIdPerAssessment() async throws {
        let (sut, _, _) = makeSUT()

        let first = try await sut.execute(location: "A")
        let second = try await sut.execute(location: "B")

        XCTAssertNotEqual(first.id, second.id)
    }
}
