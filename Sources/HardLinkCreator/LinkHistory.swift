import Foundation
import Combine

struct LinkRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let sourcePath: String
    let targetPath: String
    let completedAt: Date
    let fileCount: Int

    var sourceURL: URL { URL(fileURLWithPath: sourcePath) }
    var targetURL: URL { URL(fileURLWithPath: targetPath) }
}

@MainActor
final class LinkHistoryStore: ObservableObject {
    @Published private(set) var records: [LinkRecord] = []
    @Published private(set) var storageError: String?
    let storageURL: URL

    init(storageURL: URL? = nil) {
        if let storageURL {
            self.storageURL = storageURL
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.storageURL = support.appendingPathComponent("Hard Linker", isDirectory: true)
                .appendingPathComponent("history.json")
        }
        load()
    }

    func record(_ jobs: [HardLinkSuccess]) {
        guard !jobs.isEmpty else { return }
        let newRecords = jobs.map { success in
            LinkRecord(id: UUID(), sourcePath: success.job.source.standardizedFileURL.path,
                       targetPath: success.job.target.standardizedFileURL.path,
                       completedAt: Date(), fileCount: success.fileCount)
        }
        records.insert(contentsOf: newRecords, at: 0)
        persist()
    }

    func forget(_ id: UUID) {
        records.removeAll { $0.id == id }
        persist()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            records = try JSONDecoder().decode([LinkRecord].self, from: Data(contentsOf: storageURL))
            storageError = nil
        } catch {
            storageError = "\(L("History could not be read:")) \(error.localizedDescription)"
        }
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(records)
            try data.write(to: storageURL, options: .atomic)
            storageError = nil
        } catch {
            storageError = "\(L("History could not be saved:")) \(error.localizedDescription)"
        }
    }
}
