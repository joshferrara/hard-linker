import XCTest
@testable import HardLinkCreator

final class HardLinkPlanTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()

        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HardLinkCreatorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        try super.tearDownWithError()
    }

    func testValidPlanCreatesExpectedTarget() throws {
        let source = try makeDirectory("Source")
        let destination = try makeDirectory("Destination")

        let plan = try HardLinkPlan(sources: [source], destination: destination)

        XCTAssertEqual(plan.jobs.count, 1)
        XCTAssertEqual(plan.jobs.first?.target, destination.appendingPathComponent("Source", isDirectory: true))
    }

    func testDuplicateSourceNamesAreRejected() throws {
        let firstSource = try makeDirectory("First/Source")
        let secondSource = try makeDirectory("Second/Source")
        let destination = try makeDirectory("Destination")

        XCTAssertThrowsError(try HardLinkPlan(sources: [firstSource, secondSource], destination: destination)) { error in
            guard case .duplicateTarget = error as? HardLinkValidationError else {
                return XCTFail("Expected duplicate target error, got \(error)")
            }
        }
    }

    func testExistingTargetIsRejected() throws {
        let source = try makeDirectory("Source")
        let destination = try makeDirectory("Destination")
        _ = try makeDirectory("Destination/Source")

        XCTAssertThrowsError(try HardLinkPlan(sources: [source], destination: destination)) { error in
            guard case .targetExists = error as? HardLinkValidationError else {
                return XCTFail("Expected target exists error, got \(error)")
            }
        }
    }

    func testDestinationInsideSourceIsRejected() throws {
        let source = try makeDirectory("Source")
        let destination = try makeDirectory("Source/Destination")

        XCTAssertThrowsError(try HardLinkPlan(sources: [source], destination: destination)) { error in
            guard case .destinationInsideSource = error as? HardLinkValidationError else {
                return XCTFail("Expected destination inside source error, got \(error)")
            }
        }
    }

    func testRunnerCreatesHardLinkedFile() throws {
        let source = try makeFile("Source.txt", contents: "hard link me")
        let destination = try makeDirectory("Destination")
        let plan = try HardLinkPlan(sources: [source], destination: destination)

        let result = HardLinkRunner.createLinks(from: plan)
        let target = destination.appendingPathComponent("Source.txt")

        XCTAssertEqual(result.successCount, 1)
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
        XCTAssertEqual(try inode(for: source), try inode(for: target))
    }

    private func makeDirectory(_ relativePath: String) throws -> URL {
        let url = temporaryDirectory.appendingPathComponent(relativePath, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeFile(_ relativePath: String, contents: String) throws -> URL {
        let url = temporaryDirectory.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func inode(for url: URL) throws -> UInt64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let inode = try XCTUnwrap(attributes[.systemFileNumber] as? NSNumber)
        return inode.uint64Value
    }
}
