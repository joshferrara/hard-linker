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
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
        }
    }
}

struct ContentView: View {
    @State private var sourceFolders: [URL] = []
    @State private var destinationFolder: URL?
    @State private var status: OperationStatus?
    @State private var isCreatingLinks: Bool = false
    @State private var showingSourcePicker = false
    @State private var showingDestinationPicker = false
    @State private var isSourceDropTargeted = false
    @State private var isDestinationDropTargeted = false

    var body: some View {
        ZStack {
            LiquidGlassWindowBackground()

            VStack(alignment: .leading, spacing: 18) {
                header
                sourceSection
                destinationSection
                createButton
                statusView

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 22)
        }
        .frame(minWidth: 580, idealWidth: 620, minHeight: 610, idealHeight: 640)
        .clipShape(RoundedRectangle(cornerRadius: AppChrome.windowCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppChrome.windowCornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.32), lineWidth: 1)
        }
        .background {
            WindowConfigurator(cornerRadius: AppChrome.windowCornerRadius)
        }
    }

    private var canCreateLinks: Bool {
        !sourceFolders.isEmpty && destinationFolder != nil && !isCreatingLinks
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Hard Linker")
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Create space-efficient hard-linked copies with native macOS controls.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 72)

            Spacer(minLength: 12)

            Image(systemName: "link.badge.plus")
                .font(.system(size: 22, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
                .frame(width: 42, height: 42)
                .background(.thinMaterial, in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(.white.opacity(0.36), lineWidth: 1)
                }
        }
        .padding(.bottom, 2)
    }

    private var sourceSection: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Label("Sources", systemImage: "tray.and.arrow.down")
                        .font(.headline)
                    Spacer()
                    if !sourceFolders.isEmpty {
                        Text("\(sourceFolders.count) selected")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(.thinMaterial, in: Capsule())
                    }
                    Button {
                        guard !isCreatingLinks else { return }
                        showingSourcePicker = true
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isCreatingLinks)
                }

                dropZone(minHeight: 162, isTargeted: isSourceDropTargeted) {
                    if sourceFolders.isEmpty {
                        EmptyDropContent(
                            systemImage: "doc.badge.plus",
                            title: "Drop files or folders here",
                            subtitle: "or choose them from Finder"
                        )
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 8) {
                                ForEach(sourceFolders, id: \.self) { source in
                                    sourceRow(source)
                                }
                            }
                            .padding(10)
                        }
                        .frame(maxHeight: 202)
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
    }

    private var destinationSection: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Label("Destination", systemImage: "folder")
                        .font(.headline)
                    Spacer()
                    Button {
                        guard !isCreatingLinks else { return }
                        showingDestinationPicker = true
                    } label: {
                        Label(destinationFolder == nil ? "Choose" : "Change", systemImage: "folder.badge.plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isCreatingLinks)
                }

                dropZone(minHeight: 100, isTargeted: isDestinationDropTargeted) {
                    if let destinationFolder {
                        HStack(spacing: 12) {
                            Image(systemName: "folder.fill")
                                .font(.title3)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.tint)
                                .frame(width: 30, height: 30)
                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

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
                            subtitle: "linked copies will be created inside it"
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
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(LiquidPrimaryButtonStyle())
        .controlSize(.large)
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
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(status.color.opacity(0.34), lineWidth: 1)
            }
            .shadow(color: status.color.opacity(0.08), radius: 12, y: 6)
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
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.26), lineWidth: 1)
        }
    }

    private func pathLabel(for url: URL) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(url.lastPathComponent)
                .font(.system(.body, design: .rounded))
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
        .buttonStyle(GlassIconButtonStyle())
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
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.accentColor.opacity(isTargeted ? 0.18 : 0.08),
                                    Color.cyan.opacity(isTargeted ? 0.12 : 0.04),
                                    Color.orange.opacity(isTargeted ? 0.10 : 0.03)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .blendMode(.plusLighter)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(
                            isTargeted ? Color.accentColor.opacity(0.66) : Color.white.opacity(0.30),
                            style: StrokeStyle(lineWidth: isTargeted ? 2 : 1, dash: isTargeted ? [] : [7, 6])
                        )
                }

            content()
                .padding(8)
        }
        .frame(minHeight: minHeight)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .animation(.easeInOut(duration: 0.18), value: isTargeted)
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

private enum AppChrome {
    static let windowCornerRadius: CGFloat = 28
    static let panelCornerRadius: CGFloat = 22
}

private struct LiquidGlassWindowBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .overlay {
                LinearGradient(
                    colors: [
                        Color.accentColor.opacity(colorScheme == .dark ? 0.22 : 0.16),
                        Color.cyan.opacity(colorScheme == .dark ? 0.16 : 0.12),
                        Color.orange.opacity(colorScheme == .dark ? 0.10 : 0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .overlay {
                Color(nsColor: .windowBackgroundColor)
                    .opacity(colorScheme == .dark ? 0.10 : 0.20)
            }
    }
}

private struct GlassPanel<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: AppChrome.panelCornerRadius, style: .continuous)
                    .fill(.thinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: AppChrome.panelCornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(colorScheme == .dark ? 0.10 : 0.36),
                                        Color.accentColor.opacity(colorScheme == .dark ? 0.08 : 0.05),
                                        .clear
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: AppChrome.panelCornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(colorScheme == .dark ? 0.16 : 0.42), lineWidth: 1)
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.20 : 0.08), radius: 20, x: 0, y: 12)
    }
}

private struct LiquidPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(isEnabled ? Color.white : Color.secondary)
            .tint(isEnabled ? .white : .secondary)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: isEnabled
                                ? [Color.accentColor, Color.cyan.opacity(0.82)]
                                : [Color.secondary.opacity(0.18), Color.secondary.opacity(0.10)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.white.opacity(configuration.isPressed && isEnabled ? 0.10 : 0.0))
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.white.opacity(isEnabled ? 0.38 : 0.16), lineWidth: 1)
            }
            .shadow(color: Color.accentColor.opacity(isEnabled ? 0.22 : 0), radius: 14, y: 8)
            .scaleEffect(configuration.isPressed && isEnabled ? 0.99 : 1)
            .opacity(isEnabled ? 1 : 0.68)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
            .animation(.easeInOut(duration: 0.16), value: isEnabled)
    }
}

private struct GlassIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? Color.secondary : Color.secondary.opacity(0.45))
            .frame(width: 28, height: 28)
            .background {
                Circle()
                    .fill(.thinMaterial)
                    .overlay {
                        Circle()
                            .fill(Color.secondary.opacity(configuration.isPressed ? 0.12 : 0.05))
                    }
            }
            .overlay {
                Circle()
                    .strokeBorder(.white.opacity(0.24), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed && isEnabled ? 0.94 : 1)
            .opacity(isEnabled ? 1 : 0.6)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct WindowConfigurator: NSViewRepresentable {
    let cornerRadius: CGFloat

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
        guard let window else { return }

        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.styleMask.insert(.fullSizeContentView)

        guard let contentView = window.contentView else { return }
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = cornerRadius
        contentView.layer?.cornerCurve = .continuous
        contentView.layer?.masksToBounds = true
    }
}

private struct EmptyDropContent: View {
    let systemImage: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 27, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
                .frame(width: 46, height: 46)
                .background(.thinMaterial, in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(.white.opacity(0.28), lineWidth: 1)
                }
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
        .padding(.vertical, 18)
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
