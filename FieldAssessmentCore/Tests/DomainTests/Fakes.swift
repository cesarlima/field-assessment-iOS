import Foundation
@testable import Domain

enum FakeError: Error, Equatable {
    case notFound
    case diskFull
}

actor FakeAssessmentRepository: AssessmentRepository {
    private(set) var saved: [Assessment] = []

    func save(_ assessment: Assessment) async throws {
        saved.append(assessment)
    }

    func fetch(id: UUID) async throws -> Assessment {
        guard let match = saved.last(where: { $0.id == id }) else { throw FakeError.notFound }
        return match
    }

    func fetchAll() async throws -> [Assessment] {
        saved
    }
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
