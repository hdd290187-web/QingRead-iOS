import Foundation

// The seam exercises File Provider and commit failures without claiming an iCloud
// account can be simulated. Release uses only the real coordinated implementation.
struct ImportEnvironment {
    var stage: (URL, URL, @escaping @Sendable (ImportStage) -> Void) async throws -> StagedDocument
    var beforeCommit: (URL) throws -> Void

    static var live: ImportEnvironment {
        ImportEnvironment(stage: { source, directory, progress in
            try await Task.detached(priority: .userInitiated) {
                try DocumentStager.copyIntoPrivateDirectory(source: source, directory: directory, progress: progress)
            }.value
        }, beforeCommit: { _ in })
    }
}
