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

    /// Runs inside `update`, just before the write lands, and may replace what
    /// is stored. This is how a second writer is dropped into the window
    /// between a use case's read and its write, deterministically.
    private var beforeUpdate: (@Sendable () -> Assessment?)?

    /// Makes every update collide, for testing what happens when the retries
    /// run out.
    private var alwaysStale = false

    init(seed: [Assessment] = []) {
        for assessment in seed { stored[assessment.id] = assessment }
    }

    func onBeforeUpdate(_ hook: @escaping @Sendable () -> Assessment?) {
        beforeUpdate = hook
    }

    func failEveryUpdateAsStale() {
        alwaysStale = true
    }

    /// Writes with no checks at all, standing in for whatever else in the app
    /// got there first.
    func overwrite(_ assessment: Assessment) {
        stored[assessment.id] = assessment
    }

    func insert(_ assessment: Assessment) async throws {
        stored[assessment.id] = assessment
        inserted.append(assessment)
    }

    func update(_ assessment: Assessment) async throws {
        if let replacement = beforeUpdate?() {
            stored[replacement.id] = replacement
            beforeUpdate = nil
        }
        guard let existing = stored[assessment.id] else {
            throw AssessmentRepositoryError.notFound(assessment.id)
        }
        guard !alwaysStale, existing.version == assessment.version - 1 else {
            throw AssessmentRepositoryError.staleWrite(id: assessment.id,
                                                       expected: assessment.version - 1,
                                                       found: existing.version)
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

    /// Runs while the media is being filed — the window AddEvidence holds open
    /// between reading the assessment and writing it back.
    private var duringStore: (@Sendable () async -> Void)?

    init(failure: Error? = nil) {
        self.failure = failure
    }

    func onStore(_ hook: @escaping @Sendable () async -> Void) {
        duringStore = hook
    }

    func store(_ file: CapturedFile, as id: UUID) async throws -> String {
        if let failure { throw failure }
        if let duringStore {
            self.duringStore = nil
            await duringStore()
        }
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
