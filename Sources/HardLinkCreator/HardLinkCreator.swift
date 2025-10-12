import SwiftUI
import UniformTypeIdentifiers
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
    @State private var statusMessage: String = ""
    @State private var isCreatingLinks: Bool = false
    @State private var showingSourcePicker = false
    @State private var showingDestinationPicker = false

    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 3) {
                Text("Create hard links between folders using the")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text("cp -al")
                    .font(.system(.subheadline, design: .monospaced))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.gray.opacity(0.15))
                    .cornerRadius(4)
                Text("command.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // Source folders section
            VStack(alignment: .leading, spacing: 8) {
                Text("Source Files or Folders:")
                    .font(.headline)

                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.1))
                        .frame(minHeight: 100)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [5]))
                        )

                    VStack {
                        if sourceFolders.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "doc.badge.plus")
                                    .font(.title2)
                                    .foregroundColor(.secondary)
                                Text("Drop files or folders here or click to select")
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            LazyVStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(sourceFolders.enumerated()), id: \.offset) { index, folder in
                                    HStack {
                                        Image(systemName: folder.hasDirectoryPath ? "folder.fill" : "doc.fill")
                                            .foregroundColor(.accentColor)
                                        Text(folder.lastPathComponent)
                                            .font(.system(.body, design: .monospaced))
                                        Spacer()
                                        Button(action: {
                                            sourceFolders.remove(at: index)
                                        }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.red)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 8)
                                }
                            }
                        }
                    }
                    .padding()
                }
                .onTapGesture {
                    showingSourcePicker = true
                }
                .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
                    handleSourceDrop(providers: providers)
                }
                .fileImporter(isPresented: $showingSourcePicker, allowedContentTypes: [UTType.item], allowsMultipleSelection: true) { result in
                    handleSourcePickerResult(result)
                }
            }

            // Destination folder section
            VStack(alignment: .leading, spacing: 8) {
                Text("Destination Folder:")
                    .font(.headline)

                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.1))
                        .frame(height: 80)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [5]))
                        )

                    VStack {
                        if let destinationFolder = destinationFolder {
                            HStack {
                                Image(systemName: "folder.fill")
                                    .foregroundColor(.accentColor)
                                Text(destinationFolder.lastPathComponent)
                                    .font(.system(.body, design: .monospaced))
                                Spacer()
                                Button(action: {
                                    self.destinationFolder = nil
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 8)
                        } else {
                            VStack(spacing: 8) {
                                Image(systemName: "folder")
                                    .font(.title2)
                                    .foregroundColor(.secondary)
                                Text("Drop destination folder here or click to select")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding()
                }
                .onTapGesture {
                    showingDestinationPicker = true
                }
                .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
                    handleDestinationDrop(providers: providers)
                }
                .fileImporter(isPresented: $showingDestinationPicker, allowedContentTypes: [UTType.folder], allowsMultipleSelection: false) { result in
                    handleDestinationPickerResult(result)
                }
            }

            // Create button
            Button(action: createHardLinks) {
                HStack {
                    if isCreatingLinks {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                    Text(isCreatingLinks ? "Creating Links..." : "Create Hard Links")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(canCreateLinks ? Color.accentColor : Color.gray.opacity(0.3))
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .disabled(!canCreateLinks || isCreatingLinks)

            // Status message
            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.subheadline)
                    .foregroundColor(statusMessage.contains("Error") ? .red : .green)
                    .padding(.horizontal)
            }

            Spacer()
        }
        .padding(20)
        .frame(minWidth: 400, idealWidth: 400, minHeight: 400, idealHeight: 500)
    }

    private var canCreateLinks: Bool {
        !sourceFolders.isEmpty && destinationFolder != nil
    }

    private func handleSourceDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    DispatchQueue.main.async {
                        if !sourceFolders.contains(url) {
                            sourceFolders.append(url)
                        }
                    }
                }
            }
        }
        return true
    }

    private func handleDestinationDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
            if let data = item as? Data,
               let url = URL(dataRepresentation: data, relativeTo: nil),
               url.hasDirectoryPath {
                DispatchQueue.main.async {
                    destinationFolder = url
                }
            }
        }
        return true
    }

    private func handleSourcePickerResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                if !sourceFolders.contains(url) {
                    sourceFolders.append(url)
                }
            }
        case .failure(let error):
            statusMessage = "Error selecting source files or folders: \(error.localizedDescription)"
        }
    }

    private func handleDestinationPickerResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let url = urls.first, url.hasDirectoryPath {
                destinationFolder = url
            }
        case .failure(let error):
            statusMessage = "Error selecting destination folder: \(error.localizedDescription)"
        }
    }

    private func createHardLinks() {
        guard let destinationFolder = destinationFolder else { return }

        isCreatingLinks = true
        statusMessage = ""

        Task {
            var allSuccess = true
            var errorMessages: [String] = []

            for sourceFolder in sourceFolders {
                let sourcePath = sourceFolder.path(percentEncoded: false)
                let destinationPath = destinationFolder.path(percentEncoded: false)
                let targetPath = "\(destinationPath)/\(sourceFolder.lastPathComponent)"

                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/cp")
                process.arguments = ["-al", sourcePath, targetPath]

                let pipe = Pipe()
                process.standardError = pipe

                do {
                    try process.run()
                    process.waitUntilExit()

                    if process.terminationStatus != 0 {
                        let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
                        let errorString = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                        errorMessages.append("Failed to link \(sourceFolder.lastPathComponent): \(errorString)")
                        allSuccess = false
                    }
                } catch {
                    errorMessages.append("Failed to execute cp command for \(sourceFolder.lastPathComponent): \(error.localizedDescription)")
                    allSuccess = false
                }
            }

            await MainActor.run {
                isCreatingLinks = false

                if allSuccess {
                    let itemWord = sourceFolders.count == 1 ? "item" : "items"
                    statusMessage = "Successfully created hard links for \(sourceFolders.count) \(itemWord)"
                } else {
                    statusMessage = "Completed with errors:\n" + errorMessages.joined(separator: "\n")
                }
            }
        }
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
