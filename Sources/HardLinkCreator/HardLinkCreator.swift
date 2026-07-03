import SwiftUI
import UniformTypeIdentifiers
import AppKit
import Sparkle

@main
struct HardLinkCreatorApp: App {
    private let updaterController: SPUStandardUpdaterController

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var body: some Scene {
        WindowGroup("") {
            ContentView()
        }
        .defaultSize(CGSize(width: 760, height: 620))
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
        }
    }
}

struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var sourceFolders: [URL] = []
    @State private var destinationFolder: URL?
    @State private var status: OperationStatus?
    @State private var isCreatingLinks: Bool = false
    @State private var showingSourcePicker = false
    @State private var showingDestinationPicker = false
    @State private var isSourceDropTargeted = false
    @State private var isDestinationDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                WindowSurfaceBackground()

                VStack(alignment: .leading, spacing: 18) {
                    sourceSection
                    destinationSection
                    statusView

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 28)
                .padding(.top, 28)
                .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            footer
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Color.clear
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
        }
        .background(WindowSurfaceBackground())
        .background(WindowAppearanceConfigurator())
        .frame(minWidth: 600, idealWidth: 760, minHeight: 430, idealHeight: 620)
    }

    private var canCreateLinks: Bool {
        !sourceFolders.isEmpty && destinationFolder != nil && !isCreatingLinks
    }

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Label("Sources", systemImage: "tray.and.arrow.down")
                    .font(.headline)
                Spacer()
                if !sourceFolders.isEmpty {
                    Text("\(sourceFolders.count) selected")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color.secondary.opacity(0.13))
                        )
                }
            }

            dropZone(minHeight: 150, isTargeted: isSourceDropTargeted) {
                if sourceFolders.isEmpty {
                    EmptyDropContent(
                        systemImage: "doc.badge.plus",
                        title: "Drop files or folders here",
                        subtitle: "Click to choose from Finder"
                    )
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(sourceFolders, id: \.self) { source in
                                sourceRow(source)
                            }
                        }
                        .padding(8)
                    }
                    .frame(maxHeight: 164)
                }
            }
            .onTapGesture {
                guard !isCreatingLinks else { return }
                showingSourcePicker = true
            }
            .onDrop(of: [UTType.fileURL], isTargeted: $isSourceDropTargeted) { providers in
                handleSourceDrop(providers: providers)
            }
            .fileImporter(isPresented: $showingSourcePicker, allowedContentTypes: [UTType.item], allowsMultipleSelection: true) { result in
                handleSourcePickerResult(result)
            }
        }
    }

    private var destinationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Label("Destination", systemImage: "folder")
                    .font(.headline)
                Spacer()
            }

            dropZone(minHeight: 106, isTargeted: isDestinationDropTargeted) {
                if let destinationFolder {
                    HStack(spacing: 12) {
                        Image(systemName: "folder.fill")
                            .font(.title3)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.tint)
                            .frame(width: 28, height: 28)

                        pathLabel(for: destinationFolder)

                        Spacer(minLength: 8)

                        removeButton {
                            self.destinationFolder = nil
                            status = nil
                        }
                    }
                    .padding(12)
                } else {
                    EmptyDropContent(
                        systemImage: "folder.badge.plus",
                        title: "Drop a destination folder here",
                        subtitle: "Click to choose from Finder"
                    )
                }
            }
            .onTapGesture {
                guard !isCreatingLinks else { return }
                showingDestinationPicker = true
            }
            .onDrop(of: [UTType.fileURL], isTargeted: $isDestinationDropTargeted) { providers in
                handleDestinationDrop(providers: providers)
            }
            .fileImporter(isPresented: $showingDestinationPicker, allowedContentTypes: [UTType.folder], allowsMultipleSelection: false) { result in
                handleDestinationPickerResult(result)
            }
        }
    }

    private var footer: some View {
        HStack {
            createButton
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var createButton: some View {
        Button(action: createHardLinks) {
            HStack(spacing: 8) {
                if isCreatingLinks {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "link")
                }
                Text(isCreatingLinks ? "Creating Links..." : "Create Hard Links")
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PrimaryActionButtonStyle())
        .disabled(!canCreateLinks)
    }

    @ViewBuilder
    private var statusView: some View {
        if let status {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: status.systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(status.color)
                    .frame(width: 20)

                Text(status.message)
                    .font(.subheadline)
                    .foregroundStyle(status.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)

                Spacer(minLength: 0)
            }
            .padding(12)
            .background(status.color.opacity(colorScheme == .dark ? 0.14 : 0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(status.color.opacity(0.26), lineWidth: 1)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func sourceRow(_ source: URL) -> some View {
        HStack(spacing: 10) {
            Image(systemName: source.isExistingDirectory ? "folder.fill" : "doc.fill")
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 24)

            pathLabel(for: source)

            Spacer(minLength: 8)

            removeButton {
                sourceFolders.removeAll { $0 == source }
                status = nil
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 10)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.30), lineWidth: 1)
        }
    }

    private var rowBackground: Color {
        Color(nsColor: .controlBackgroundColor).opacity(colorScheme == .dark ? 0.48 : 0.82)
    }

    private func pathLabel(for url: URL) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(url.lastPathComponent)
                .font(.body)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(url.displayPath)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func removeButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .imageScale(.medium)
        }
        .buttonStyle(IconButtonStyle())
        .disabled(isCreatingLinks)
        .help("Remove")
        .accessibilityLabel("Remove")
    }

    private func dropZone<Content: View>(
        minHeight: CGFloat,
        isTargeted: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(dropZoneBackground)
                .overlay {
                    if isTargeted {
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .fill(Color.accentColor.opacity(colorScheme == .dark ? 0.16 : 0.09))
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .strokeBorder(
                            isTargeted ? Color.accentColor.opacity(0.70) : Color(nsColor: .separatorColor).opacity(0.24),
                            style: StrokeStyle(lineWidth: isTargeted ? 2 : 1, dash: isTargeted ? [] : [8, 8])
                        )
                }
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.20 : 0.07), radius: 8, x: 0, y: 3)

            content()
                .padding(10)
        }
        .frame(minHeight: minHeight)
        .contentShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .animation(.easeInOut(duration: 0.18), value: isTargeted)
    }

    private var dropZoneBackground: Color {
        Color(nsColor: .textBackgroundColor).opacity(colorScheme == .dark ? 0.36 : 0.86)
    }

    private func handleSourceDrop(providers: [NSItemProvider]) -> Bool {
        guard !isCreatingLinks else { return false }

        var acceptedProvider = false
        for provider in providers {
            guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { continue }
            acceptedProvider = true

            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                guard error == nil, let url = URL.fileURL(from: item) else { return }
                DispatchQueue.main.async {
                    appendSource(url)
                }
            }
        }

        return acceptedProvider
    }

    private func handleDestinationDrop(providers: [NSItemProvider]) -> Bool {
        guard !isCreatingLinks else { return false }
        guard let provider = providers.first else { return false }
        guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { return false }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
            guard error == nil, let url = URL.fileURL(from: item) else { return }
            DispatchQueue.main.async {
                setDestination(url)
            }
        }
        return true
    }

    private func handleSourcePickerResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                appendSource(url)
            }
        case .failure(let error):
            status = .failure("Could not select sources: \(error.localizedDescription)")
        }
    }

    private func handleDestinationPickerResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let url = urls.first {
                setDestination(url)
            }
        case .failure(let error):
            status = .failure("Could not select destination: \(error.localizedDescription)")
        }
    }

    private func appendSource(_ url: URL) {
        let fileURL = url.fileURL
        guard !sourceFolders.contains(where: { $0.normalizedPath == fileURL.normalizedPath }) else { return }

        sourceFolders.append(fileURL)
        status = nil
    }

    private func setDestination(_ url: URL) {
        let fileURL = url.fileURL
        guard fileURL.isExistingDirectory else {
            status = .failure("Choose a folder for the destination.")
            return
        }

        destinationFolder = fileURL
        status = nil
    }

    private func createHardLinks() {
        guard let destinationFolder = destinationFolder else { return }

        isCreatingLinks = true
        let selectedSources = sourceFolders
        let destination = destinationFolder

        do {
            let plan = try HardLinkPlan(sources: selectedSources, destination: destination)
            status = .working("Creating hard links for \(plan.jobs.count) \(plan.jobs.count == 1 ? "item" : "items")...")

            Task.detached(priority: .userInitiated) {
                let result = HardLinkRunner.createLinks(from: plan)

                await MainActor.run {
                    isCreatingLinks = false

                    if result.failures.isEmpty {
                        status = .success("Created hard links for \(result.successCount) \(result.successCount == 1 ? "item" : "items").")
                    } else {
                        status = .failure(result.summary)
                    }
                }
            }
        } catch {
            isCreatingLinks = false
            status = .failure(error.localizedDescription)
        }
    }
}

private struct WindowSurfaceBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .windowBackgroundColor))
            .overlay {
                LinearGradient(
                    colors: [
                        Color.white.opacity(colorScheme == .dark ? 0.02 : 0.24),
                        Color.accentColor.opacity(colorScheme == .dark ? 0.05 : 0.035),
                        Color.black.opacity(colorScheme == .dark ? 0.16 : 0.02)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
    }
}

private struct WindowAppearanceConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configure(window: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(window: nsView.window)
        }
    }

    private func configure(window: NSWindow?) {
        window?.titlebarSeparatorStyle = .none
    }
}

private struct IconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? Color.secondary : Color.secondary.opacity(0.45))
            .frame(width: 24, height: 24)
            .background {
                Circle()
                    .fill(Color.secondary.opacity(configuration.isPressed ? 0.13 : 0.06))
            }
            .scaleEffect(configuration.isPressed && isEnabled ? 0.94 : 1)
            .opacity(isEnabled ? 1 : 0.6)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct PrimaryActionButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? Color.white : Color.secondary)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, minHeight: 36)
            .background {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .scaleEffect(configuration.isPressed && isEnabled ? 0.99 : 1)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
            .animation(.easeInOut(duration: 0.16), value: isEnabled)
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if isEnabled {
            return Color.accentColor.opacity(isPressed ? 0.84 : 1)
        }

        return Color(nsColor: .controlBackgroundColor).opacity(colorScheme == .dark ? 0.36 : 0.72)
    }

    private var borderColor: Color {
        isEnabled
            ? Color.white.opacity(colorScheme == .dark ? 0.20 : 0.34)
            : Color(nsColor: .separatorColor).opacity(0.42)
    }
}

private struct EmptyDropContent: View {
    let systemImage: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
                .frame(width: 38, height: 38)
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }
}

struct OperationStatus {
    enum Kind {
        case working
        case success
        case failure
    }

    let kind: Kind
    let message: String

    static func working(_ message: String) -> OperationStatus {
        OperationStatus(kind: .working, message: message)
    }

    static func success(_ message: String) -> OperationStatus {
        OperationStatus(kind: .success, message: message)
    }

    static func failure(_ message: String) -> OperationStatus {
        OperationStatus(kind: .failure, message: message)
    }

    var color: Color {
        switch kind {
        case .working:
            return .secondary
        case .success:
            return .green
        case .failure:
            return .red
        }
    }

    var systemImage: String {
        switch kind {
        case .working:
            return "hourglass"
        case .success:
            return "checkmark.circle.fill"
        case .failure:
            return "exclamationmark.triangle.fill"
        }
    }
}

struct HardLinkPlan {
    let jobs: [HardLinkJob]
    let securityScopedURLs: [URL]

    init(sources: [URL], destination: URL, fileManager: FileManager = .default) throws {
        guard !sources.isEmpty else {
            throw HardLinkValidationError.noSources
        }

        guard destination.isExistingDirectory(fileManager: fileManager) else {
            throw HardLinkValidationError.destinationNotFolder(destination.displayPath)
        }

        var seenTargets: [String: URL] = [:]
        var plannedJobs: [HardLinkJob] = []

        for source in sources {
            let sourceURL = source.standardizedFileURL
            let destinationURL = destination.standardizedFileURL

            guard sourceURL.exists(fileManager: fileManager) else {
                throw HardLinkValidationError.sourceMissing(sourceURL.displayPath)
            }

            if sourceURL.isExistingDirectory(fileManager: fileManager),
               destinationURL.isSameOrDescendant(of: sourceURL) {
                throw HardLinkValidationError.destinationInsideSource(
                    source: sourceURL.displayPath,
                    destination: destinationURL.displayPath
                )
            }

            let targetURL = destinationURL.appendingPathComponent(
                sourceURL.lastPathComponent,
                isDirectory: sourceURL.isExistingDirectory(fileManager: fileManager)
            )
            let targetPath = targetURL.normalizedPath

            if let duplicateSource = seenTargets[targetPath] {
                throw HardLinkValidationError.duplicateTarget(
                    target: targetURL.displayPath,
                    firstSource: duplicateSource.displayPath,
                    secondSource: sourceURL.displayPath
                )
            }

            guard !targetURL.exists(fileManager: fileManager) else {
                throw HardLinkValidationError.targetExists(targetURL.displayPath)
            }

            seenTargets[targetPath] = sourceURL
            plannedJobs.append(HardLinkJob(source: sourceURL, target: targetURL))
        }

        jobs = plannedJobs
        securityScopedURLs = Array(Set(sources.map(\.fileURL) + [destination.fileURL]))
    }
}

struct HardLinkJob {
    let source: URL
    let target: URL
}

enum HardLinkValidationError: LocalizedError, Equatable {
    case noSources
    case destinationNotFolder(String)
    case sourceMissing(String)
    case destinationInsideSource(source: String, destination: String)
    case duplicateTarget(target: String, firstSource: String, secondSource: String)
    case targetExists(String)

    var errorDescription: String? {
        switch self {
        case .noSources:
            return "Choose at least one source."
        case .destinationNotFolder(let path):
            return "The destination is not a folder: \(path)"
        case .sourceMissing(let path):
            return "The source no longer exists: \(path)"
        case .destinationInsideSource(let source, let destination):
            return "The destination cannot be the source folder or inside it.\nSource: \(source)\nDestination: \(destination)"
        case .duplicateTarget(let target, let firstSource, let secondSource):
            return "Two sources would create the same target:\nTarget: \(target)\nSource 1: \(firstSource)\nSource 2: \(secondSource)"
        case .targetExists(let path):
            return "A file or folder already exists at the target path: \(path)"
        }
    }
}

struct HardLinkRunner {
    static func createLinks(from plan: HardLinkPlan) -> HardLinkResult {
        SecurityScopedAccess.withAccess(to: plan.securityScopedURLs) {
            var successCount = 0
            var failures: [HardLinkFailure] = []

            for job in plan.jobs {
                if let message = runCopy(for: job) {
                    failures.append(HardLinkFailure(sourceName: job.source.lastPathComponent, message: message))
                } else {
                    successCount += 1
                }
            }

            return HardLinkResult(successCount: successCount, failures: failures)
        }
    }

    private static func runCopy(for job: HardLinkJob) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/cp")
        process.arguments = ["-al", job.source.path, job.target.path]

        let errorPipe = Pipe()
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let processMessage = String(data: errorData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let message = processMessage?.isEmpty == false
                    ? processMessage!
                    : "cp exited with status \(process.terminationStatus). Hard links must be created on the same volume."
                return message
            }

            return nil
        } catch {
            return "Could not run cp: \(error.localizedDescription)"
        }
    }
}

struct HardLinkResult {
    let successCount: Int
    let failures: [HardLinkFailure]

    var summary: String {
        let itemWord = failures.count == 1 ? "item" : "items"
        let failureLines = failures.map { "\($0.sourceName): \($0.message)" }
        return "Could not create hard links for \(failures.count) \(itemWord).\n" + failureLines.joined(separator: "\n")
    }
}

struct HardLinkFailure {
    let sourceName: String
    let message: String
}

enum SecurityScopedAccess {
    static func withAccess<Result>(to urls: [URL], perform work: () -> Result) -> Result {
        var accessedURLs: [URL] = []

        for url in urls {
            if url.startAccessingSecurityScopedResource() {
                accessedURLs.append(url)
            }
        }

        defer {
            for url in accessedURLs.reversed() {
                url.stopAccessingSecurityScopedResource()
            }
        }

        return work()
    }
}

extension URL {
    static func fileURL(from item: NSSecureCoding?) -> URL? {
        switch item {
        case let url as URL:
            return url.fileURL
        case let data as Data:
            return URL(dataRepresentation: data, relativeTo: nil)?.fileURL
        case let string as String:
            return URL(fileURLWithPath: string).fileURL
        default:
            return nil
        }
    }

    var fileURL: URL {
        isFileURL ? self : URL(fileURLWithPath: path)
    }

    var displayPath: String {
        standardizedFileURL.path
    }

    var normalizedPath: String {
        standardizedFileURL.resolvingSymlinksInPath().path
    }

    var isExistingDirectory: Bool {
        isExistingDirectory()
    }

    func exists(fileManager: FileManager = .default) -> Bool {
        fileManager.fileExists(atPath: path)
    }

    func isExistingDirectory(fileManager: FileManager = .default) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    func isSameOrDescendant(of ancestor: URL) -> Bool {
        let ancestorPath = ancestor.normalizedPath
        let path = normalizedPath

        if path == ancestorPath {
            return true
        }

        let prefix = ancestorPath.hasSuffix("/") ? ancestorPath : ancestorPath + "/"
        return path.hasPrefix(prefix)
    }
}

// MARK: - Sparkle Update Menu View
struct CheckForUpdatesView: View {
    let updater: SPUUpdater

    var body: some View {
        Button("Check for Updates…") {
            updater.checkForUpdates()
        }
    }
}
