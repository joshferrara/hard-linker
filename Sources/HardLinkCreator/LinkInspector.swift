import Foundation

struct FileIdentity: Hashable {
    let device: UInt64
    let inode: UInt64
}

struct FileFact {
    let identity: FileIdentity
    let linkCount: Int
}

struct LinkGroup: Identifiable {
    let subjectPath: String
    let linkCount: Int
    let paths: [String]
    var id: String { subjectPath }
    var isComplete: Bool { paths.count >= linkCount }
}

struct LinkSearchReport {
    let groups: [LinkGroup]
    let scannedFiles: Int
    let scannedRoots: [String]
    let warnings: [String]
    let cancelled: Bool
}

struct LinkVerification {
    let sourceFiles: Int
    let matchingFiles: Int
    let missing: [String]
    let mismatched: [String]
    let extra: [String]
    let warnings: [String]
    var isComplete: Bool { missing.isEmpty && mismatched.isEmpty && extra.isEmpty && warnings.isEmpty }
}

final class ScanCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func cancel() { lock.lock(); value = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
}

enum LinkInspector {
    private static var fm: FileManager { FileManager.default }
    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    static func fact(at url: URL) -> FileFact? {
        guard (try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]).isSymbolicLink) != true,
              (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
              let attrs = try? fm.attributesOfItem(atPath: url.path),
              let device = attrs[.systemNumber] as? NSNumber,
              let inode = attrs[.systemFileNumber] as? NSNumber,
              let count = attrs[.referenceCount] as? NSNumber else { return nil }
        return FileFact(identity: FileIdentity(device: device.uint64Value, inode: inode.uint64Value),
                        linkCount: count.intValue)
    }

    static func fileCount(at url: URL) -> Int {
        if fact(at: url) != nil { return 1 }
        guard isDirectory(url) else { return 0 }
        var count = 0
        var warnings: [String] = []
        walk(url, cancel: nil, warnings: &warnings) { child in
            if fact(at: child) != nil { count += 1 }
        }
        return count
    }

    static func search(subject: URL, records: [LinkRecord], extraScopes: [URL],
                       cancel: ScanCancellation, progress: ((Int) -> Void)? = nil) -> LinkSearchReport {
        var subjects: [FileIdentity: (path: String, count: Int)] = [:]
        var warnings: [String] = []
        let subjectURL = subject.standardizedFileURL
        if let item = fact(at: subjectURL), item.linkCount > 1 {
            subjects[item.identity] = (subjectURL.path, item.linkCount)
        } else if fact(at: subjectURL) != nil {
            return LinkSearchReport(groups: [], scannedFiles: 0, scannedRoots: [], warnings: [], cancelled: false)
        } else if isDirectory(subjectURL) {
            walk(subjectURL, cancel: cancel, warnings: &warnings) { url in
                if let item = fact(at: url), item.linkCount > 1 {
                    subjects[item.identity] = (url.path, item.linkCount)
                }
            }
        } else {
            warnings.append("Selected item is not a readable regular file or folder: \(subjectURL.path)")
        }

        if cancel.isCancelled {
            return LinkSearchReport(groups: [], scannedFiles: 0, scannedRoots: [], warnings: warnings, cancelled: true)
        }

        var found: [FileIdentity: Set<String>] = [:]
        for (identity, item) in subjects { found[identity] = [item.path] }
        let candidateURLs = records.flatMap { [$0.sourceURL, $0.targetURL] } + extraScopes + [subjectURL]
        let subjectDevices = Set(subjects.keys.map(\.device))
        let scopes = compactScopes(candidateURLs).filter { root in
            guard let device = (try? fm.attributesOfItem(atPath: root.path)[.systemNumber] as? NSNumber)?.uint64Value else {
                return true // Keep missing or unreadable locations so the scan reports them.
            }
            return subjectDevices.contains(device)
        }
        var scanned = 0
        var scannedRoots: [String] = []

        for root in scopes {
            if cancel.isCancelled { break }
            guard fm.fileExists(atPath: root.path) else {
                warnings.append("Missing search location: \(root.path)")
                continue
            }
            scannedRoots.append(root.path)
            let inspect: (URL) -> Void = { url in
                scanned += 1
                if let item = fact(at: url), subjects[item.identity] != nil {
                    found[item.identity, default: []].insert(url.standardizedFileURL.path)
                }
                if scanned % 200 == 0 { progress?(scanned) }
            }
            if isDirectory(root) {
                walk(root, cancel: cancel, warnings: &warnings, visit: inspect)
            } else {
                inspect(root)
            }
        }
        progress?(scanned)
        let groups = subjects.map { identity, item in
            LinkGroup(subjectPath: item.path, linkCount: item.count,
                      paths: Array(found[identity, default: []]).sorted())
        }.sorted { $0.subjectPath.localizedStandardCompare($1.subjectPath) == .orderedAscending }
        return LinkSearchReport(groups: groups, scannedFiles: scanned, scannedRoots: scannedRoots,
                                warnings: warnings, cancelled: cancel.isCancelled)
    }

    static func verify(_ record: LinkRecord, cancel: ScanCancellation) -> LinkVerification {
        var warnings: [String] = []
        let source = record.sourceURL
        let target = record.targetURL
        if let a = fact(at: source) {
            let b = fact(at: target)
            return LinkVerification(sourceFiles: 1, matchingFiles: b?.identity == a.identity ? 1 : 0,
                                    missing: b == nil ? [target.path] : [],
                                    mismatched: b != nil && b?.identity != a.identity ? [target.path] : [],
                                    extra: [], warnings: [])
        }
        guard isDirectory(source), isDirectory(target) else {
            return LinkVerification(sourceFiles: 0, matchingFiles: 0, missing: [source.path, target.path],
                                    mismatched: [], extra: [], warnings: [])
        }
        var sourceFiles: [String: FileIdentity] = [:]
        var targetFiles: [String: FileIdentity] = [:]
        walk(source, cancel: cancel, warnings: &warnings) { url in
            if let fact = fact(at: url) { sourceFiles[relative(url, to: source)] = fact.identity }
        }
        walk(target, cancel: cancel, warnings: &warnings) { url in
            if let fact = fact(at: url) { targetFiles[relative(url, to: target)] = fact.identity }
        }
        if cancel.isCancelled { warnings.append("Verification cancelled") }
        let missing = Set(sourceFiles.keys).subtracting(targetFiles.keys).sorted()
        let extra = Set(targetFiles.keys).subtracting(sourceFiles.keys).sorted()
        let mismatched = Set(sourceFiles.keys).intersection(targetFiles.keys)
            .filter { sourceFiles[$0] != targetFiles[$0] }.sorted()
        return LinkVerification(sourceFiles: sourceFiles.count,
                                matchingFiles: sourceFiles.count - missing.count - mismatched.count,
                                missing: missing, mismatched: mismatched, extra: extra, warnings: warnings)
    }

    private static func relative(_ url: URL, to root: URL) -> String {
        String(url.standardizedFileURL.path.dropFirst(root.standardizedFileURL.path.count + 1))
    }

    private static func compactScopes(_ urls: [URL]) -> [URL] {
        let normalized = Array(Set(urls.map { $0.standardizedFileURL.resolvingSymlinksInPath().path }))
            .sorted { $0.count < $1.count }
        var kept: [String] = []
        for path in normalized {
            if !kept.contains(where: { path == $0 || path.hasPrefix($0 + "/") && isDirectory(URL(fileURLWithPath: $0)) }) {
                kept.append(path)
            }
        }
        return kept.map { URL(fileURLWithPath: $0) }
    }

    private static func walk(_ root: URL, cancel: ScanCancellation?, warnings: inout [String],
                             visit: (URL) -> Void) {
        guard let rootDevice = (try? fm.attributesOfItem(atPath: root.path)[.systemNumber] as? NSNumber)?.uint64Value else {
            warnings.append("Cannot read folder: \(root.path)")
            return
        }
        var errors: [String] = []
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                                            options: [], errorHandler: { url, error in
            errors.append("\(url.path): \(error.localizedDescription)")
            return true
        }) else {
            warnings.append("Cannot scan folder: \(root.path)")
            return
        }
        for case let url as URL in enumerator {
            if cancel?.isCancelled == true { break }
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if values?.isSymbolicLink == true { enumerator.skipDescendants(); continue }
            if let device = (try? fm.attributesOfItem(atPath: url.path)[.systemNumber] as? NSNumber)?.uint64Value,
               device != rootDevice { enumerator.skipDescendants(); continue }
            if values?.isDirectory == true { continue }
            visit(url)
        }
        warnings.append(contentsOf: errors)
    }
}
