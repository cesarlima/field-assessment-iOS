import Foundation
import XCTest
@testable import Domain

enum FakeError: Error, Equatable {
    case diskFull
}

actor FakeAssessmentRepository: AssessmentRepository {
    private var stored: [UUID: Assessment] = [:]
    private(set) var inserted: [Assessment] = []
    private(set) var updated: [Assessment] = []

    init(seed: [Assessment] = []) {
        for assessment in seed { stored[assessment.id] = assessment }
    }

    func insert(_ assessment: Assessment) async throws {
        stored[assessment.id] = assessment
        inserted.append(assessment)
    }

    func update(_ assessment: Assessment) async throws {
        guard stored[assessment.id] != nil else {
            throw AssessmentRepositoryError.notFound(assessment.id)
        }
        stored[assessment.id] = assessment
        updated.append(assessment)
    }

    func fetch(id: UUID) async throws -> Assessment {
        guard let assessment = stored[id] else {
            throw AssessmentRepositoryError.notFound(id)
        }
        return assessment
    }

    func fetchAll() async throws -> [Assessment] {
        Array(stored.values)
    }

    /// Writes made, in order, so a test can tell an update from an insert.
    var writes: Int { inserted.count + updated.count }
}

actor FakeEvidenceFileStore: EvidenceFileStore {
    private(set) var stored: [UUID] = []
    private var failure: Error?

    init(failure: Error? = nil) {
        self.failure = failure
    }

    func store(_ file: CapturedFile, as id: UUID) async throws -> String {
        if let failure { throw failure }
        stored.append(id)
        return "\(id.uuidString).\(file.url.pathExtension)"
    }
}

func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ onError: (Error) -> Void
) async {
    do {
        _ = try await expression()
        XCTFail("Expected an error, got none", file: file, line: line)
    } catch {
        onError(error)
    }
}
