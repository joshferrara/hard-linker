import XCTest
@testable import HardLinkCreator

final class LinkInspectorTests: XCTestCase {
    func testCreateRecordSearchAndVerifyFolder() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("HardLinkerPlusTest-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("Source", isDirectory: true)
        let destination = root.appendingPathComponent("Destination", isDirectory: true)
        try FileManager.default.createDirectory(at: source.appendingPathComponent("Nested"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let first = source.appendingPathComponent("one.txt")
        let second = source.appendingPathComponent("Nested/two.txt")
        try "one".write(to: first, atomically: true, encoding: .utf8)
        try "two".write(to: second, atomically: true, encoding: .utf8)

        let result = try HardLinkRunner.createLinks(from: HardLinkPlan(sources: [source], destination: destination))
        XCTAssertEqual(result.successCount, 1)
        XCTAssertEqual(result.successfulJobs.first?.fileCount, 2)
        let target = destination.appendingPathComponent("Source", isDirectory: true)

        let historyURL = root.appendingPathComponent("history.json")
        let record = await MainActor.run { () -> LinkRecord in
            let store = LinkHistoryStore(storageURL: historyURL)
            store.record(result.successfulJobs)
            return store.records[0]
        }
        let reloaded = await MainActor.run { LinkHistoryStore(storageURL: historyURL).records }
        XCTAssertEqual(reloaded, [record])

        let verification = LinkInspector.verify(record, cancel: ScanCancellation())
        XCTAssertTrue(verification.isComplete)
        XCTAssertEqual(verification.matchingFiles, 2)

        let fileSearch = LinkInspector.search(subject: first, records: [record], extraScopes: [], cancel: ScanCancellation())
        XCTAssertEqual(fileSearch.groups.count, 1)
        XCTAssertEqual(fileSearch.groups[0].paths.count, 2)
        XCTAssertTrue(fileSearch.groups[0].isComplete)

        let folderSearch = LinkInspector.search(subject: source, records: [record], extraScopes: [], cancel: ScanCancellation())
        XCTAssertEqual(folderSearch.groups.count, 2)
        XCTAssertTrue(folderSearch.groups.allSatisfy(\.isComplete))

        let limitedSearch = LinkInspector.search(subject: first, records: [], extraScopes: [], cancel: ScanCancellation())
        XCTAssertEqual(limitedSearch.groups[0].paths.count, 1)
        XCTAssertFalse(limitedSearch.groups[0].isComplete)

        let targetFirst = target.appendingPathComponent("one.txt")
        XCTAssertEqual(LinkInspector.fact(at: first)?.identity, LinkInspector.fact(at: targetFirst)?.identity)

        let unrelated = root.appendingPathComponent("unlinked.txt")
        try "unlinked".write(to: unrelated, atomically: true, encoding: .utf8)
        let noLinks = LinkInspector.search(subject: unrelated, records: [record], extraScopes: [], cancel: ScanCancellation())
        XCTAssertTrue(noLinks.groups.isEmpty)

        let extra = target.appendingPathComponent("extra.txt")
        try "extra".write(to: extra, atomically: true, encoding: .utf8)
        let withExtra = LinkInspector.verify(record, cancel: ScanCancellation())
        XCTAssertEqual(withExtra.extra, ["extra.txt"])
        XCTAssertFalse(withExtra.isComplete)
    }
}
