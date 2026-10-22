import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct HistoryPanel: View {
    @ObservedObject var store: LinkHistoryStore
    @State private var verification: [UUID: LinkVerification] = [:]
    @State private var verifying: UUID?
    @State private var pendingForget: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let error = store.storageError {
                Text(error).foregroundStyle(.red).textSelection(.enabled)
            }
            if store.records.isEmpty {
                Label(L("No completed jobs yet."), systemImage: "clock.arrow.circlepath")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(store.records) { record in
                            VStack(alignment: .leading, spacing: 7) {
                                HStack {
                                    Image(systemName: "link.circle.fill").foregroundStyle(.blue)
                                    Text(record.sourceURL.lastPathComponent).font(.headline)
                                    Spacer()
                                    Text(record.completedAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Text(record.sourcePath).font(.caption).textSelection(.enabled)
                                Text("→ " + record.targetPath).font(.caption).textSelection(.enabled)
                                HStack {
                                    Text("\(record.fileCount) " + L("files"))
                                        .font(.caption).foregroundStyle(.secondary)
                                    Spacer()
                                    Button(L("Verify")) { verify(record) }
                                        .disabled(verifying != nil)
                                    Button(L("Forget")) { pendingForget = record.id }
                                }
                                if let report = verification[record.id] {
                                    Text("\(L("Matching files")): \(report.matchingFiles)/\(report.sourceFiles) · \(L("Missing")): \(report.missing.count) · \(L("Changed")): \(report.mismatched.count) · \(L("Extra")): \(report.extra.count)")
                                        .font(.caption)
                                        .foregroundStyle(report.isComplete ? .green : .orange)
                                    if !report.warnings.isEmpty {
                                        Text(report.warnings.prefix(2).joined(separator: "\n"))
                                            .font(.caption).foregroundStyle(.orange)
                                    }
                                }
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
        .confirmationDialog(L("Forget this record?"), isPresented: Binding(
            get: { pendingForget != nil }, set: { if !$0 { pendingForget = nil } }
        )) {
            Button(L("Forget"), role: .destructive) {
                if let id = pendingForget { store.forget(id); verification[id] = nil }
                pendingForget = nil
            }
            Button(L("Cancel"), role: .cancel) { pendingForget = nil }
        } message: {
            Text(L("Only the record is removed. Files stay in place."))
        }
    }

    private func verify(_ record: LinkRecord) {
        verifying = record.id
        let cancellation = ScanCancellation()
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                LinkInspector.verify(record, cancel: cancellation)
            }.value
            verification[record.id] = result
            verifying = nil
        }
    }
}

struct SearchPanel: View {
    let records: [LinkRecord]
    @State private var subject: URL?
    @State private var extraScopes: [URL] = []
    @State private var report: LinkSearchReport?
    @State private var running = false
    @State private var scanned = 0
    @State private var cancellation: ScanCancellation?
    @State private var searchID: UUID?
    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button(L("Choose file or folder"), systemImage: "doc.badge.magnifyingglass") { chooseSubject() }
                Text(subject?.path ?? L("No file selected."))
                    .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                Spacer()
            }
            Text(L("Drop a file or folder anywhere here to select it for search."))
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(L("Add folders"), systemImage: "folder.badge.plus") { chooseScopes() }
                Text("\(L("Recorded locations")): \(records.count * 2) · \(L("Search folders")): \(extraScopes.count)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !extraScopes.isEmpty {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(extraScopes, id: \.path) { url in
                            HStack(spacing: 4) {
                                Text(url.lastPathComponent).lineLimit(1)
                                Button { extraScopes.removeAll { $0 == url } } label: { Image(systemName: "xmark.circle.fill") }
                                    .buttonStyle(.plain)
                            }
                            .padding(6)
                            .background(.quaternary, in: Capsule())
                        }
                    }
                }
            }
            Text(records.isEmpty ? L("No recorded locations. Add a search folder to look beyond the selected item.") : L("Search scope is limited to recorded and selected folders."))
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(L("Search hard links"), systemImage: "magnifyingglass") { startSearch() }
                    .buttonStyle(.borderedProminent)
                    .disabled(subject == nil || running)
                if running {
                    ProgressView()
                    Text("\(L("Scanned files")): \(scanned)").font(.caption)
                    Button(L("Cancel")) { cancellation?.cancel() }
                }
            }
            Divider()
            if let report {
                HStack {
                    Text("\(L("Scanned files")): \(report.scannedFiles) · \(L("Search folders")): \(report.scannedRoots.count)")
                        .font(.caption).foregroundStyle(.secondary)
                    if report.cancelled { Text(L("Search was cancelled; results are incomplete.")).foregroundStyle(.orange) }
                }
                if !report.warnings.isEmpty {
                    Text("\(L("Scan warnings")): " + report.warnings.prefix(3).joined(separator: " | "))
                        .font(.caption).foregroundStyle(.orange).textSelection(.enabled)
                }
                if report.groups.isEmpty {
                    Text(L("No hard-linked files found in this folder."))
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(report.groups) { group in
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(URL(fileURLWithPath: group.subjectPath).lastPathComponent).font(.headline)
                                    Text("\(L("links found")): \(group.paths.count) / \(L("total links")): \(group.linkCount)")
                                        .font(.caption)
                                        .foregroundStyle(group.isComplete ? .green : .orange)
                                    ForEach(group.paths, id: \.self) { path in
                                        Text(path).font(.caption).textSelection(.enabled)
                                    }
                                    if !group.isComplete {
                                        Text(L("Other links may be outside the selected scope."))
                                            .font(.caption).foregroundStyle(.orange)
                                    }
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }
                }
            } else {
                Spacer()
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isDropTargeted ? Color.accentColor : .clear, lineWidth: 2)
                .padding(8)
                .allowsHitTesting(false)
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted, perform: handleSubjectDrop)
    }

    private func chooseSubject() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK {
            if let url = panel.url { selectSubject(url) }
        }
    }

    private func handleSubjectDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            return false
        }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
            guard error == nil, let url = URL.fileURL(from: item) else { return }
            DispatchQueue.main.async { selectSubject(url) }
        }
        return true
    }

    private func selectSubject(_ url: URL) {
        cancellation?.cancel()
        searchID = nil
        cancellation = nil
        running = false
        scanned = 0
        subject = url.fileURL
        report = nil
    }

    private func chooseScopes() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            for url in panel.urls where !extraScopes.contains(url) { extraScopes.append(url) }
            report = nil
        }
    }

    private func startSearch() {
        guard let subject else { return }
        let control = ScanCancellation()
        let id = UUID()
        searchID = id
        cancellation = control
        running = true
        scanned = 0
        report = nil
        let records = records
        let scopes = extraScopes
        Task {
            let finished = await Task.detached(priority: .userInitiated) {
                LinkInspector.search(subject: subject, records: records, extraScopes: scopes,
                                     cancel: control, progress: { count in
                    DispatchQueue.main.async { if searchID == id { scanned = count } }
                })
            }.value
            guard searchID == id else { return }
            report = finished
            running = false
            cancellation = nil
            searchID = nil
        }
    }
}
