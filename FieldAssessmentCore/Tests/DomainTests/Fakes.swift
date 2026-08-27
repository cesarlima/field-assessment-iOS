import Foundation
import XCTest
@testable import Domain

enum FakeError: Error, Equatable {
    case diskFull

    /// The source was already moved out of temporary storage by an earlier
    /// attempt. Real `FileManager` reports this as "no such file".
    case sourceIsGone
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

    /// Fails one write and then behaves, standing in for a transient problem
    /// the caller is expected to retry.
    private var nextUpdateFailure: Error?

    init(seed: [Assessment] = []) {
        for assessment in seed { stored[assessment.id] = assessment }
    }

    func onBeforeUpdate(_ hook: @escaping @Sendable () -> Assessment?) {
        beforeUpdate = hook
    }

    func failEveryUpdateAsStale() {
        alwaysStale = true
    }

    func failNextUpdate(with error: Error) {
        nextUpdateFailure = error
    }

    /// Writes with no checks at all, standing in for whatever else in the app
    /// got there first.
    func overwrite(_ assessment: Assessment) {
        stored[assessment.id] = assessment
    }

    func insert(_ assessment: Assessment) async throws {
        guard stored[assessment.id] == nil else {
            throw AssessmentRepositoryError.alreadyExists(assessment.id)
        }
        stored[assessment.id] = assessment
        inserted.append(assessment)
    }

    func update(_ assessment: Assessment) async throws {
        if let failure = nextUpdateFailure {
            nextUpdateFailure = nil
            throw failure
        }
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

    /// Writes made, in order, so a test can tell an update from an insert.
    var writes: Int { inserted.count + updated.count }
}

actor FakeEvidenceFileStore: EvidenceFileStore {
    /// Ids whose file is sitting in the evidence directory.
    private(set) var stored: [UUID] = []
    private(set) var removed: [UUID] = []

    /// Sources already moved out of temporary storage. Moving is what makes a
    /// second attempt from the same source impossible, so the fake has to
    /// model it — otherwise a retry test would pass for the wrong reason.
    private var consumed: Set<URL> = []

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

    func store(_ file: CapturedFile) async throws -> String {
        if let failure { throw failure }
        if let duringStore {
            self.duringStore = nil
            await duringStore()
        }

        let name = "\(file.id.uuidString).\(file.url.pathExtension)"

        // Already filed under this id: adopt it, leave the source alone.
        guard !stored.contains(file.id) else { return name }

        guard !consumed.contains(file.url) else { throw FakeError.sourceIsGone }
        consumed.insert(file.url)
        stored.append(file.id)
        return name
    }

    func remove(_ id: UUID) async throws {
        stored.removeAll { $0 == id }
        removed.append(id)
    }
}

/// Hands out one date per call, in order, so an attempt can be told apart
/// from the retry after it. The last date repeats once the list runs out.
final class SteppingClock: @unchecked Sendable {
    private let lock = NSLock()
    private var times: [Date]

    init(_ times: [Date]) {
        precondition(!times.isEmpty)
        self.times = times
    }

    var now: @Sendable () -> Date {
        { [self] in
            lock.lock()
            defer { lock.unlock() }
            return times.count > 1 ? times.removeFirst() : times[0]
        }
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
