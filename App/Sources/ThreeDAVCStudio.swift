import AppKit
import SwiftUI
import UniformTypeIdentifiers

private let skippedNoMVCExitCode: Int32 = 20
private let fileAccessExitCode: Int32 = 126

@main
struct ThreeDAVCStudioApp: App {
    var body: some Scene {
        WindowGroup {
            StudioView()
                .frame(minWidth: 880, minHeight: 620)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Support") {
                Button("3D AVC Studio Support") {
                    AppSupportActions.openSupport()
                }
                Button("Privacy Information") {
                    AppSupportActions.openPrivacy()
                }
                Button("Product Page") {
                    AppSupportActions.openProductPage()
                }
                Divider()
                Button("Copy Release Readiness") {
                    AppSupportActions.copyReleaseReadiness()
                }
            }
        }
    }
}

struct QueueItem: Identifiable, Hashable {
    enum Status: String {
        case queued = "Queued"
        case running = "Running"
        case finished = "Done"
        case skipped = "Skipped"
        case failed = "Failed"
    }

    let id = UUID()
    let url: URL
    var status: Status = .queued

    var outputName: String {
        url.deletingPathExtension().lastPathComponent + "_sbs_h265_fast.mp4"
    }
}

struct StudioView: View {
    @State private var queue: [QueueItem] = []
    @State private var outputFolder: URL?
    @State private var cameraProfile = "sony-3d-avc"
    @State private var codec = "h265-vt"
    @State private var deinterlace = "60"
    @State private var bitrate = "12000k"
    @State private var logs = ""
    @State private var isRunning = false
    @State private var currentProcess: Process?
    @State private var showingDecoderSetup = false
    @State private var engineStatusRevision = UUID()

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    private var engineStatus: EngineStatus {
        _ = engineStatusRevision
        return EngineStatus.detect()
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            controls
            Divider()
            queueAndLog
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showingDecoderSetup) {
            DecoderSetupView {
                engineStatusRevision = UUID()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("3D AVC Studio")
                    .font(.system(size: 24, weight: .semibold))
                Text("v\(appVersion) - Sony 3D AVC MVC to SBS HEVC")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                AppSupportActions.openSupport()
            } label: {
                Label("Support", systemImage: "questionmark.circle")
            }
            .help("Open 3D AVC Studio support.")

            Button {
                AppSupportActions.openPrivacy()
            } label: {
                Label("Privacy", systemImage: "hand.raised")
            }
            .help("Open privacy information.")

            releaseBadge
            engineBadge
            Button("Decoder Setup...") {
                showingDecoderSetup = true
            }
            Button(isRunning ? "Cancel" : "Convert") {
                isRunning ? cancel() : start()
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!isRunning && (queue.isEmpty || !engineStatus.canConvert))
        }
        .padding(20)
    }

    private var engineBadge: some View {
        Label(engineStatus.title, systemImage: engineStatus.icon)
            .foregroundStyle(engineStatus.canConvert ? .green : .orange)
            .help(engineStatus.help)
    }

    private var releaseBadge: some View {
        Label(engineStatus.releaseTitle, systemImage: engineStatus.releaseIcon)
            .foregroundStyle(engineStatus.isStoreReady ? .green : .orange)
            .help(engineStatus.releaseHelp)
    }

    private var controls: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                Button("Choose Files") { chooseFiles() }
                Button("Choose Folder") { chooseInputFolder() }
                Button("Output Folder") { chooseOutputFolder() }
                Button("Use Source Folders") { outputFolder = nil }
                    .disabled(outputFolder == nil)
                Spacer()
                Button("Clear Queue") { queue.removeAll() }
                    .disabled(isRunning || queue.isEmpty)
            }

            HStack(spacing: 16) {
                Picker("Camera", selection: $cameraProfile) {
                    Text("Sony 3D AVC / AVCHD 3D").tag("sony-3d-avc")
                }
                .frame(width: 210)

                Picker("Codec", selection: $codec) {
                    Text("H.265 Fast Apple").tag("h265-vt")
                }
                .frame(width: 210)

                Spacer()
                outputLabel
            }

            HStack(spacing: 16) {
                Picker("Deinterlace", selection: $deinterlace) {
                    Text("60p").tag("60")
                    Text("30p").tag("30")
                    Text("Off").tag("off")
                }
                .pickerStyle(.segmented)
                .frame(width: 220)

                Picker("Bitrate", selection: $bitrate) {
                    Text("8 Mbps").tag("8000k")
                    Text("12 Mbps").tag("12000k")
                    Text("16 Mbps").tag("16000k")
                    Text("24 Mbps").tag("24000k")
                }
                .frame(width: 150)

                Spacer()
            }
        }
        .padding(20)
    }

    private var outputLabel: some View {
        Group {
            if let outputFolder {
                Label(outputFolder.path, systemImage: "folder")
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Label("Same as source", systemImage: "folder.badge.gearshape")
            }
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: 280, alignment: .trailing)
    }

    private var queueAndLog: some View {
        HSplitView {
            queueView
                .frame(minWidth: 320)
            logView
                .frame(minWidth: 420)
        }
        .padding(20)
    }

    private var queueView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Queue")
                    .font(.headline)
                Spacer()
                Text("\(queue.count) files")
                    .foregroundStyle(.secondary)
            }

            List(queue) { item in
                HStack(spacing: 10) {
                    Image(systemName: icon(for: item.status))
                        .foregroundStyle(color(for: item.status))
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.url.lastPathComponent)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(item.status.rawValue)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 3)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var logView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Log")
                    .font(.headline)
                Spacer()
                Button("Save Diagnostics") { saveDiagnostics() }
                    .disabled(isRunning)
                Button("Clear") { logs = "" }
                    .disabled(isRunning)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    Text(logs.isEmpty ? startupLog : logs)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .id("log-end")
                }
                .onChange(of: logs) { _ in
                    proxy.scrollTo("log-end", anchor: .bottom)
                }
            }
            .padding(10)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var startupLog: String {
        if engineStatus.canConvert {
            return "Ready.\nEngine: \(engineStatus.help)"
        }
        return "Ready.\n\(engineStatus.help)"
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = Self.mediaTypes
        if panel.runModal() == .OK {
            addFiles(panel.urls)
        }
    }

    private func chooseInputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let folder = panel.url {
            addFiles(filesInFolder(folder))
        }
    }

    private func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK {
            outputFolder = panel.url
        }
    }

    private func start() {
        guard !queue.isEmpty, engineStatus.canConvert else { return }
        let selectedOutputFolder = outputFolder
        let selectedCameraProfile = cameraProfile
        let selectedCodec = codec
        let selectedDeinterlace = deinterlace
        let selectedBitrate = bitrate
        let itemCount = queue.count
        isRunning = true
        logs = ""

        Task.detached {
            for index in 0..<itemCount {
                if Task.isCancelled { break }
                await setStatus(.running, at: index)
                let item = await MainActor.run { queue[index] }
                let baseFolder = selectedOutputFolder ?? item.url.deletingLastPathComponent()
                let output = baseFolder.appendingPathComponent(item.outputName)
                await append("Converting \(item.url.lastPathComponent) -> \(output.lastPathComponent)\n")

                let code = await runEngine(
                    input: item.url,
                    output: output,
                    profile: selectedCameraProfile,
                    codec: selectedCodec,
                    deinterlace: selectedDeinterlace,
                    bitrate: selectedBitrate
                )

                if code == skippedNoMVCExitCode {
                    await append("\nSkipped \(item.url.lastPathComponent): no complete Sony 3D AVC MVC dependent view found.\n\n")
                    await setStatus(.skipped, at: index)
                    continue
                }
                if code == fileAccessExitCode {
                    await append("\nFile access failed. Choose an output folder or add files by choosing their parent folder.\n")
                    await setStatus(.failed, at: index)
                    break
                }
                if code != 0 {
                    await append("\nFailed with exit code \(code).\n")
                    await setStatus(.failed, at: index)
                    break
                }
                await append("\nFinished \(output.path)\n\n")
                await setStatus(.finished, at: index)
            }

            await MainActor.run {
                isRunning = false
                currentProcess = nil
            }
        }
    }

    private func cancel() {
        currentProcess?.terminate()
        isRunning = false
        appendNow("\nCancelled.\n")
    }

    private func addFiles(_ urls: [URL]) {
        let existing = Set(queue.map { $0.url.standardizedFileURL.path })
        let items = normalizedInputFiles(urls)
            .filter { !existing.contains($0.standardizedFileURL.path) }
            .map { QueueItem(url: $0) }
        queue.append(contentsOf: items)
    }

    private func filesInFolder(_ folder: URL) -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }
        return enumerator.compactMap { $0 as? URL }
    }

    private func normalizedInputFiles(_ urls: [URL]) -> [URL] {
        urls
            .filter { ["mts", "m2ts"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    nonisolated private func runEngine(
        input: URL,
        output: URL,
        profile: String,
        codec: String,
        deinterlace: String,
        bitrate: String
    ) async -> Int32 {
        guard let command = EngineStatus.detect().command else {
            await append("Conversion engine is not bundled in this build.\n")
            return 127
        }

        let inputAccess = SecurityScopedAccess(input)
        let outputDirectory = output.deletingLastPathComponent()
        let outputAccess = SecurityScopedAccess(outputDirectory)
        guard Self.verifyOutputDirectory(outputDirectory) else {
            await append(
                """
                Cannot write to \(outputDirectory.path).
                Picking individual files may not grant permission to create sibling output files. Try choosing an output folder or adding the whole source folder.

                """
            )
            _ = inputAccess
            _ = outputAccess
            return fileAccessExitCode
        }

        let process = Process()
        process.executableURL = command.executable
        process.arguments = command.arguments(
            input: input,
            output: output,
            profile: profile,
            codec: codec,
            deinterlace: deinterlace,
            bitrate: bitrate
        )
        process.environment = command.environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        await MainActor.run { currentProcess = process }

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { await append(Self.filteredLog(text)) }
        }

        do {
            try process.run()
            process.waitUntilExit()
            pipe.fileHandleForReading.readabilityHandler = nil
            _ = inputAccess
            _ = outputAccess
            return process.terminationStatus
        } catch {
            await append("Could not start conversion engine: \(error.localizedDescription)\n")
            _ = inputAccess
            _ = outputAccess
            return 127
        }
    }

    @MainActor
    private func setStatus(_ status: QueueItem.Status, at index: Int) {
        guard queue.indices.contains(index) else { return }
        queue[index].status = status
    }

    @MainActor
    private func append(_ text: String) {
        guard !text.isEmpty else { return }
        logs += text
        if logs.count > 80_000 {
            logs = String(logs.suffix(80_000))
        }
    }

    private func appendNow(_ text: String) {
        logs += text
    }

    private func saveDiagnostics() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "3D-AVC-Studio-Diagnostics-\(Self.timestampForFilename()).txt"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try diagnosticsReport().write(to: url, atomically: true, encoding: .utf8)
            appendNow("\nSaved diagnostics: \(url.lastPathComponent)\n")
        } catch {
            appendNow("\nCould not save diagnostics: \(error.localizedDescription)\n")
        }
    }

    private func diagnosticsReport() -> String {
        let status = engineStatus
        let outputMode = outputFolder == nil ? "source folders" : "selected output folder"
        let queueSummary = Dictionary(grouping: queue, by: { $0.status.rawValue })
            .map { "\($0.key)=\($0.value.count)" }
            .sorted()
            .joined(separator: ", ")
        let fileLines = queue.isEmpty
            ? "No queued files."
            : queue.map { "- \($0.url.lastPathComponent): \($0.status.rawValue) -> \($0.outputName)" }
                .joined(separator: "\n")

        return """
        3D AVC Studio Diagnostics
        Generated: \(Self.isoTimestamp())
        App version: \(appVersion)

        Engine:
        - Title: \(status.title)
        - Release: \(status.releaseTitle)
        - Can convert: \(status.canConvert)
        - Store ready: \(status.isStoreReady)
        - Conversion complete: \(status.conversionComplete)
        - Bundled decoder: \(status.hasBundledDecoder)
        - Local decoder: \(LocalDecoderStore.isInstalled)
        - Local decoder location: \(LocalDecoderStore.displayLocation)
        - Decoder approved: \(status.decoderApproved)
        - Notices bundled: \(status.hasNotices)
        - Help: \(status.help)
        - Release help: \(status.releaseHelp)

        Settings:
        - Camera profile: \(cameraProfile)
        - Codec: \(codec)
        - Deinterlace: \(deinterlace)
        - Bitrate: \(bitrate)
        - Output mode: \(outputMode)

        Queue:
        - Count: \(queue.count)
        - Status summary: \(queueSummary.isEmpty ? "none" : queueSummary)
        \(fileLines)

        Recent log:
        \(Self.sanitizedLog(logs.isEmpty ? startupLog : logs, queue: queue, outputFolder: outputFolder))

        Privacy:
        This diagnostics file is created locally and is not uploaded by the app.
        It intentionally uses file names instead of full selected media paths.
        """
    }

    private func icon(for status: QueueItem.Status) -> String {
        switch status {
        case .queued: return "clock"
        case .running: return "play.circle.fill"
        case .finished: return "checkmark.circle.fill"
        case .skipped: return "forward.circle.fill"
        case .failed: return "xmark.octagon.fill"
        }
    }

    private func color(for status: QueueItem.Status) -> Color {
        switch status {
        case .queued: return .secondary
        case .running: return .blue
        case .finished: return .green
        case .skipped: return .orange
        case .failed: return .red
        }
    }

    nonisolated private static var mediaTypes: [UTType] {
        [UTType(filenameExtension: "mts"), UTType(filenameExtension: "m2ts")].compactMap { $0 }
    }

    nonisolated private static func filteredLog(_ text: String) -> String {
        text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { line in
                !line.contains("Completed Decoding frame")
            }
            .joined(separator: "\n")
    }

    nonisolated private static func verifyOutputDirectory(_ directory: URL) -> Bool {
        let probe = directory.appendingPathComponent(".3davc-write-test-\(UUID().uuidString)")
        do {
            try Data().write(to: probe, options: .withoutOverwriting)
            try FileManager.default.removeItem(at: probe)
            return true
        } catch {
            return false
        }
    }

    nonisolated private static func isoTimestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    nonisolated private static func timestampForFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: Date())
    }

    nonisolated private static func sanitizedLog(_ text: String, queue: [QueueItem], outputFolder: URL?) -> String {
        var sanitized = text
        let home = NSHomeDirectory()
        if !home.isEmpty {
            sanitized = sanitized.replacingOccurrences(of: home, with: "~")
        }
        for item in queue {
            sanitized = sanitized.replacingOccurrences(of: item.url.path, with: item.url.lastPathComponent)
            sanitized = sanitized.replacingOccurrences(of: item.url.deletingLastPathComponent().path, with: "[source folder]")
        }
        if let outputFolder {
            sanitized = sanitized.replacingOccurrences(of: outputFolder.path, with: "[selected output folder]")
        }
        if sanitized.count > 12_000 {
            sanitized = String(sanitized.suffix(12_000))
        }
        return sanitized
    }
}

struct DecoderSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var message = "No local MVC decoder is installed."
    @State private var isInstalled = LocalDecoderStore.isInstalled
    @State private var isWorking = false
    let onChanged: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("MVC Decoder Setup", systemImage: "puzzlepiece.extension")
                    .font(.title3.weight(.semibold))
                Spacer()
                statusLabel
            }

            Text("3D AVC Studio does not include an MVC decoder. Choose a decoder you are legally allowed to use and the app will keep a private copy for conversion.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Only choose a decoder you trust. Decoder Setup runs the selected executable locally when you test or convert media.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Text("Required decoder command")
                    .font(.headline)
                Text("mvcdecoder decode COMBINED_MVC.h264 LEFT.yuv RIGHT.yuv --width W --height H")
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Text("The decoder must write complete left/right YUV420p files. A raw h264-tools/JM ldecod binary does not use this command shape without an adapter.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Installed location")
                    .font(.headline)
                Text(LocalDecoderStore.displayLocation)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            Text(message)
                .font(.callout)
                .foregroundStyle(isInstalled ? .green : .secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Choose Decoder...") { chooseDecoder() }
                    .disabled(isWorking)
                Button("Test") { testDecoder() }
                    .disabled(isWorking || !isInstalled)
                Button("Remove") { removeDecoder() }
                    .disabled(isWorking || !isInstalled)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 620)
        .onAppear {
            refreshStatus()
            if isInstalled {
                message = "A local MVC decoder is installed."
            }
        }
    }

    private var statusLabel: some View {
        Label(isInstalled ? "Installed" : "Not Installed", systemImage: isInstalled ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            .foregroundStyle(isInstalled ? .green : .orange)
    }

    private func chooseDecoder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Install Decoder"
        panel.message = "Choose an executable MVC decoder that implements the command shown here."
        guard panel.runModal() == .OK, let source = panel.url else { return }

        isWorking = true
        defer { isWorking = false }
        do {
            try LocalDecoderStore.install(from: source)
            message = "Installed a local decoder. It is ready for the next conversion."
            refreshStatus()
        } catch {
            message = "Could not install decoder: \(error.localizedDescription)"
        }
    }

    private func testDecoder() {
        isWorking = true
        defer { isWorking = false }
        switch LocalDecoderStore.launchTest() {
        case .success(let result):
            message = result
        case .failure(let error):
            message = "Decoder test failed: \(error.localizedDescription)"
        }
        refreshStatus()
    }

    private func removeDecoder() {
        isWorking = true
        defer { isWorking = false }
        do {
            try LocalDecoderStore.remove()
            message = "Removed the local decoder."
            refreshStatus()
        } catch {
            message = "Could not remove decoder: \(error.localizedDescription)"
        }
    }

    private func refreshStatus() {
        isInstalled = LocalDecoderStore.isInstalled
        onChanged()
    }
}

enum LocalDecoderStore {
    private static let fileName = "mvcdecoder"

    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("3D AVC Studio", isDirectory: true)
    }

    static var url: URL {
        directory.appendingPathComponent(fileName)
    }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    static var displayLocation: String {
        url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    static func install(from source: URL) throws {
        let sourceValues = try source.resourceValues(forKeys: [.isRegularFileKey])
        guard sourceValues.isRegularFile == true else {
            throw DecoderStoreError.notAFile
        }

        let access = SecurityScopedAccess(source)
        _ = access
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appendingPathComponent(".mvcdecoder-\(UUID().uuidString)")
        defer { try? manager.removeItem(at: temporary) }
        try manager.copyItem(at: source, to: temporary)
        try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: temporary.path)
        try installResearchSupportFiles(for: source, manager: manager)
        try? manager.removeItem(at: url)
        try manager.moveItem(at: temporary, to: url)
        guard isInstalled else {
            throw DecoderStoreError.notExecutable
        }
    }

    static func remove() throws {
        let manager = FileManager.default
        if manager.fileExists(atPath: url.path) {
            try manager.removeItem(at: url)
        }
        try? manager.removeItem(at: researchSupportDirectory)
    }

    static func launchTest() -> Result<String, Error> {
        guard isInstalled else { return .failure(DecoderStoreError.notInstalled) }
        let process = Process()
        let nullDevice = URL(fileURLWithPath: "/dev/null")
        guard let nullHandle = try? FileHandle(forWritingTo: nullDevice) else {
            return .failure(DecoderStoreError.testUnavailable)
        }
        defer { try? nullHandle.close() }
        process.executableURL = url
        process.arguments = ["--help"]
        process.standardOutput = nullHandle
        process.standardError = nullHandle
        do {
            try process.run()
            let deadline = Date().addingTimeInterval(4)
            while process.isRunning && Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            }
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
                return .failure(DecoderStoreError.testTimedOut)
            }
            if process.terminationStatus == 0 {
                return .success("Decoder launch test passed. It responded to --help.")
            }
            return .success("Decoder launched (exit code \(process.terminationStatus)). It is installed; conversion will validate the required decoder interface.")
        } catch {
            return .failure(error)
        }
    }

    private static var researchSupportDirectory: URL {
        directory.appendingPathComponent("research-decoder", isDirectory: true)
    }

    private static func installResearchSupportFiles(for source: URL, manager: FileManager) throws {
        let bin = source.deletingLastPathComponent()
        let researchRoot = bin.deletingLastPathComponent()
        let ldecod = bin.appendingPathComponent("ldecod")
        let config = researchRoot.appendingPathComponent("h264-tools/ldecod/decoder.cfg")
        guard source.lastPathComponent == "mvcdecoder",
              manager.isExecutableFile(atPath: ldecod.path),
              manager.fileExists(atPath: config.path) else {
            return
        }

        let temporary = directory.appendingPathComponent(".research-decoder-\(UUID().uuidString)", isDirectory: true)
        defer { try? manager.removeItem(at: temporary) }
        let temporaryBin = temporary.appendingPathComponent("bin", isDirectory: true)
        let temporaryConfig = temporary.appendingPathComponent("ldecod", isDirectory: true)
        try manager.createDirectory(at: temporaryBin, withIntermediateDirectories: true)
        try manager.createDirectory(at: temporaryConfig, withIntermediateDirectories: true)
        let temporaryDecoder = temporaryBin.appendingPathComponent("ldecod")
        try manager.copyItem(at: ldecod, to: temporaryDecoder)
        try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: temporaryDecoder.path)
        try manager.copyItem(at: config, to: temporaryConfig.appendingPathComponent("decoder.cfg"))
        try? manager.removeItem(at: researchSupportDirectory)
        try manager.moveItem(at: temporary, to: researchSupportDirectory)
    }

    enum DecoderStoreError: LocalizedError {
        case notAFile, notExecutable, notInstalled, testUnavailable, testTimedOut

        var errorDescription: String? {
            switch self {
            case .notAFile: return "Choose a decoder executable file, not a folder."
            case .notExecutable: return "The selected file is not executable."
            case .notInstalled: return "No local decoder is installed."
            case .testUnavailable: return "Could not open the test output device."
            case .testTimedOut: return "The decoder did not respond within four seconds."
            }
        }
    }
}

enum AppSupportActions {
    private static let productURL = URL(string: "https://froogal.top/learn/sony-3d-avc-studio.html")!
    private static let supportURL = URL(string: "https://froogal.top/learn/sony-3d-avc-studio-support.html")!
    private static let privacyURL = URL(string: "https://froogal.top/learn/sony-3d-avc-studio-support.html#privacy")!

    static func openProductPage() {
        NSWorkspace.shared.open(productURL)
    }

    static func openSupport() {
        NSWorkspace.shared.open(supportURL)
    }

    static func openPrivacy() {
        NSWorkspace.shared.open(privacyURL)
    }

    static func copyReleaseReadiness() {
        let status = EngineStatus.detect()
        let text = """
        \(status.releaseTitle)
        Engine: \(status.title)
        \(status.releaseHelp)
        \(status.help)
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

final class SecurityScopedAccess {
    private let url: URL
    private let didStart: Bool

    init(_ url: URL) {
        self.url = url
        self.didStart = url.startAccessingSecurityScopedResource()
    }

    deinit {
        if didStart {
            url.stopAccessingSecurityScopedResource()
        }
    }
}

struct EngineStatus {
    let title: String
    let icon: String
    let help: String
    let command: EngineCommand?
    let conversionComplete: Bool
    let hasBundledDecoder: Bool
    let decoderApproved: Bool
    let hasNotices: Bool

    var canConvert: Bool {
        command != nil && conversionComplete
    }

    var isStoreReady: Bool {
        conversionComplete && hasBundledDecoder && decoderApproved && hasNotices
    }

    var releaseTitle: String {
        isStoreReady ? "Decoder Ready" : "Open Source Preview"
    }

    var releaseIcon: String {
        isStoreReady ? "checkmark.shield.fill" : "exclamationmark.shield.fill"
    }

    var releaseHelp: String {
        if isStoreReady {
            return "Bundled conversion, decoder policy, and notices are present."
        }

        var missing: [String] = []
        if !conversionComplete { missing.append("native conversion is not marked complete") }
        if !hasBundledDecoder { missing.append("bundled MVC decoder is not included") }
        if !decoderApproved { missing.append("decoder policy is not marked ready") }
        if !hasNotices { missing.append("third-party notices are not bundled") }
        return "Open-source preview: \(missing.joined(separator: ", ")). This build is sponsor-supported and does not include an MVC decoder by default."
    }

    static func detect() -> EngineStatus {
        guard let resources = Bundle.main.resourceURL else {
            return missing("App resources are unavailable.")
        }

        let nativeEngine = resources.appendingPathComponent("Engine/sony3dengine")
        let release = releaseFacts(resources: resources)
        if FileManager.default.isExecutableFile(atPath: nativeEngine.path) {
            let complete = decoderAvailable(resources: resources)
            if complete {
                return EngineStatus(
                    title: LocalDecoderStore.isInstalled ? "Local Decoder Ready" : "Native Engine",
                    icon: "checkmark.seal.fill",
                    help: LocalDecoderStore.isInstalled
                        ? "Using the local MVC decoder installed through Decoder Setup."
                        : "Using bundled native conversion engine.",
                    command: .native(nativeEngine),
                    conversionComplete: true,
                    hasBundledDecoder: release.hasBundledDecoder,
                    decoderApproved: release.decoderApproved,
                    hasNotices: release.hasNotices
                )
            }
        }

        if FileManager.default.isExecutableFile(atPath: nativeEngine.path) {
            return EngineStatus(
                title: "Native Engine Preview",
                icon: "hammer.circle.fill",
                help: "Bundled native engine can probe Sony 3D AVC MVC streams, but conversion is not complete yet.",
                command: .native(nativeEngine),
                conversionComplete: false,
                hasBundledDecoder: release.hasBundledDecoder,
                decoderApproved: release.decoderApproved,
                hasNotices: release.hasNotices
            )
        }

        return missing("No conversion engine is bundled. Build from source with Scripts/build_app.sh.")
    }

    private static func missing(_ help: String) -> EngineStatus {
        EngineStatus(
            title: "Engine Missing",
            icon: "exclamationmark.triangle.fill",
            help: help,
            command: nil,
            conversionComplete: false,
            hasBundledDecoder: false,
            decoderApproved: false,
            hasNotices: false
        )
    }

    private static func releaseFacts(resources: URL) -> (hasBundledDecoder: Bool, decoderApproved: Bool, hasNotices: Bool) {
        let decoder = resources.appendingPathComponent("Engine/mvcdecoder")
        let policy = resources.appendingPathComponent("Compliance/decoder_policy.json")
        let notices = resources.appendingPathComponent("ThirdPartyNotices.md")
        let policyText = (try? String(contentsOf: policy, encoding: .utf8)) ?? ""
        return (
            FileManager.default.isExecutableFile(atPath: decoder.path),
            policyText.contains("\"bundledInPreview\": true"),
            FileManager.default.fileExists(atPath: notices.path)
        )
    }

    private static func decoderAvailable(resources: URL) -> Bool {
        if let override = ProcessInfo.processInfo.environment["SONY3D_MVC_DECODER"],
           FileManager.default.isExecutableFile(atPath: override) {
            return true
        }
        if LocalDecoderStore.isInstalled {
            return true
        }
        let bundled = resources.appendingPathComponent("Engine/mvcdecoder")
        return FileManager.default.isExecutableFile(atPath: bundled.path)
    }
}

enum EngineCommand {
    case native(URL)

    var executable: URL {
        switch self {
        case .native(let url):
            return url
        }
    }

    var environment: [String: String] {
        switch self {
        case .native:
            var environment = ProcessInfo.processInfo.environment
            if LocalDecoderStore.isInstalled {
                environment["SONY3D_MVC_DECODER"] = LocalDecoderStore.url.path
            }
            return environment
        }
    }

    func arguments(input: URL, output: URL, profile: String, codec: String, deinterlace: String, bitrate: String) -> [String] {
        switch self {
        case .native:
            return [
                "convert",
                input.path,
                output.path,
                "--profile",
                profile,
                "--codec",
                codec,
                "--deinterlace",
                deinterlace,
                "--bitrate",
                bitrate
            ]
        }
    }
}
