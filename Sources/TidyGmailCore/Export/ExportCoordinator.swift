import Foundation

// MARK: - Export coordinator

/// Orchestrates the full export pipeline: fetch raw messages -> group by label -> write MBOX ->
/// write manifest -> create encrypted DMG -> cleanup.
public final class ExportCoordinator: Sendable {
    private let client: any GmailAPIClient
    private let dmgCreator: any DMGCreator
    private let fetchConcurrencyLimit = 5

    public init(client: any GmailAPIClient, dmgCreator: any DMGCreator = LiveDMGCreator()) {
        self.client = client
        self.dmgCreator = dmgCreator
    }

    /// Run the export. Reports progress via the callback. Supports cancellation via Task.
    ///
    /// - Parameters:
    ///   - messageIDs: IDs of the messages to export
    ///   - destination: Path for the output `.dmg` file
    ///   - passphrase: AES-256 encryption passphrase
    ///   - onProgress: Called on the caller's actor with updated progress
    /// - Returns: An `ExportSummary` on success
    public func export(
        messageIDs: [String],
        destination: URL,
        passphrase: String,
        onProgress: @Sendable @escaping (ExportProgress) -> Void
    ) async throws -> ExportSummary {
        guard !messageIDs.isEmpty else {
            throw ExportError.noMessagesSelected
        }

        let validation = PassphraseValidator.validate(passphrase)
        guard validation.isValid else {
            throw ExportError.invalidPassphrase(validation.message ?? "Too short")
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TidyGmailExport-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let dmgDestination = computeDMGDestination(from: destination)

        do {
            // Phase 1: Fetch raw messages
            let rawMessages = try await fetchRawMessages(
                ids: messageIDs,
                total: messageIDs.count,
                onProgress: onProgress
            )
            try Task.checkCancellation()

            // Phases 2-4: Write archive files (labels, MBOX, manifest)
            try await writeArchiveFiles(
                rawMessages: rawMessages,
                messageIDs: messageIDs,
                tempDir: tempDir,
                onProgress: onProgress
            )
            try Task.checkCancellation()

            // Phase 5: Set custom icon and create DMG
            try setCustomIcon(in: tempDir)
            try Task.checkCancellation()

            onProgress(ExportProgress(phase: .creatingDMG, current: 0, total: 1))

            // Remove any existing DMG at the destination
            try? FileManager.default.removeItem(at: dmgDestination)

            try await dmgCreator.createEncryptedDMG(
                sourceDirectory: tempDir,
                destination: dmgDestination,
                volumeName: "TidyGmail Export",
                passphrase: passphrase
            )

            try? FileManager.default.removeItem(at: tempDir)

            let fileAttrs = try FileManager.default.attributesOfItem(atPath: dmgDestination.path)
            let fileSize = fileAttrs[.size] as? Int64 ?? 0

            let summary = ExportSummary(
                filePath: dmgDestination,
                fileSize: fileSize,
                messageCount: messageIDs.count
            )

            onProgress(
                ExportProgress(phase: .complete, current: messageIDs.count, total: messageIDs.count)
            )
            return summary

        } catch is CancellationError {
            try? FileManager.default.removeItem(at: tempDir)
            try? FileManager.default.removeItem(at: dmgDestination)
            throw ExportError.cancelled
        } catch let error as ExportError {
            try? FileManager.default.removeItem(at: tempDir)
            throw error
        } catch {
            try? FileManager.default.removeItem(at: tempDir)
            throw ExportError.fetchFailed(error.localizedDescription)
        }
    }

    /// Verify an exported DMG by mounting it read-only and checking the manifest checksums.
    public func verify(dmgPath: URL, passphrase: String) async throws -> Bool {
        let mountPoint = try await dmgCreator.mountReadOnly(
            dmgPath: dmgPath, passphrase: passphrase)
        defer { Task { try? await dmgCreator.unmount(volumePath: mountPoint) } }

        let manifestURL = mountPoint.appendingPathComponent("manifest.json")
        let manifestData = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(ExportManifest.self, from: manifestData)

        var mboxFiles: [String: Data] = [:]
        for filename in manifest.mboxChecksums.keys {
            // Build URL by appending each path component separately
            let pathComponents = filename.split(separator: "/", omittingEmptySubsequences: false)
                .map(String.init)
            var fileURL = mountPoint
            for component in pathComponents {
                fileURL = fileURL.appendingPathComponent(component)
            }
            mboxFiles[filename] = try Data(contentsOf: fileURL)
        }

        return ManifestWriter.verify(manifest: manifest, mboxFiles: mboxFiles)
    }

    // MARK: - Private

    private func fetchRawMessages(
        ids: [String],
        total: Int,
        onProgress: @Sendable @escaping (ExportProgress) -> Void
    ) async throws -> [RawGmailMessage] {
        try await withThrowingTaskGroup(of: RawGmailMessage.self) { group in
            var iterator = ids.makeIterator()
            var collected = [RawGmailMessage]()

            // Pre-fill up to the concurrency limit
            for _ in 0..<fetchConcurrencyLimit {
                guard let id = iterator.next() else { break }
                group.addTask { try await self.client.fetchRawMessage(id: id) }
            }

            while let message = try await group.next() {
                collected.append(message)
                onProgress(
                    ExportProgress(
                        phase: .fetchingMessages,
                        current: collected.count,
                        total: total
                    ))

                if let id = iterator.next() {
                    group.addTask { try await self.client.fetchRawMessage(id: id) }
                }
            }

            return collected
        }
    }

    private func computeDMGDestination(from destination: URL) -> URL {
        let timestamp = Self.dateTimeFormatter.string(from: Date())
        let filename = "TidyGmail-Export-\(timestamp).dmg"

        if destination.hasDirectoryPath {
            return destination.appendingPathComponent(filename)
        } else if destination.pathExtension == "dmg" {
            // Replace extension with timestamped version
            let baseName = destination.deletingPathExtension().lastPathComponent
            return destination.deletingPathExtension()
                .appendingPathComponent("\(baseName)-\(timestamp).dmg")
        } else {
            // Add timestamp and .dmg extension
            return destination.appendingPathComponent("\(filename)")
        }
    }

    private func writeArchiveFiles(
        rawMessages: [RawGmailMessage],
        messageIDs: [String],
        tempDir: URL,
        onProgress: @Sendable @escaping (ExportProgress) -> Void
    ) async throws {
        // Phase 2: Fetch labels for grouping
        onProgress(ExportProgress(phase: .writingArchive, current: 0, total: 1))
        let labels = try await client.fetchLabels()
        let labelMap = Dictionary(uniqueKeysWithValues: labels.map { ($0.id, $0.name) })

        // Phase 3: Group messages by label and write MBOX files
        let mboxFiles = writeMBOXFiles(rawMessages: rawMessages, labelMap: labelMap)
        var mboxDataMap: [String: Data] = [:]

        for (filename, data) in mboxFiles {
            // Build URL by appending each path component separately
            // (filename may contain "/" for nested folder structure)
            let pathComponents = filename.split(separator: "/", omittingEmptySubsequences: false)
                .map(String.init)
            var filePath = tempDir
            for component in pathComponents {
                filePath = filePath.appendingPathComponent(component)
            }

            // Create parent directories
            try FileManager.default.createDirectory(
                at: filePath.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: filePath)
            mboxDataMap[filename] = data
        }

        try Task.checkCancellation()

        // Phase 4: Write manifest
        let manifestData = ManifestWriter.write(
            messageIDs: messageIDs,
            mboxFiles: mboxDataMap
        )
        try manifestData.write(to: tempDir.appendingPathComponent("manifest.json"))
    }

    private func setCustomIcon(in directory: URL) throws {
        guard let appIconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
        else { return }

        let volumeIconURL = directory.appendingPathComponent(".VolumeIcon.icns")
        try FileManager.default.copyItem(at: appIconURL, to: volumeIconURL)

        let setFileProcess = Process()
        setFileProcess.executableURL = URL(fileURLWithPath: "/usr/bin/SetFile")
        setFileProcess.arguments = ["-a", "C", directory.path]
        try setFileProcess.run()
        setFileProcess.waitUntilExit()
    }

    private func writeMBOXFiles(
        rawMessages: [RawGmailMessage],
        labelMap: [String: String]
    ) -> [(String, Data)] {
        // Group messages by their first label; fall back to "Unlabeled"
        var grouped: [String: [RawGmailMessage]] = [:]
        for message in rawMessages {
            let labelName =
                message.labelIds
                .compactMap { labelMap[$0] }
                .first ?? "Unlabeled"
            grouped[labelName, default: []].append(message)
        }

        // Write one MBOX per label, organized in folder hierarchy
        var result: [(String, Data)] = []
        for (labelName, messages) in grouped.sorted(by: { $0.key < $1.key }) {
            // Build folder path from label hierarchy (e.g., "Work/Projects" → "labels/Work/Projects")
            let labelComponents = labelName.split(separator: "/").map(String.init)
            var folderPath = ["labels"]
            folderPath.append(contentsOf: labelComponents)

            // Safe filename with "/" replaced by "-" for the terminal filename
            let safeName = labelName.replacingOccurrences(of: "/", with: "-")
            let filename = folderPath.joined(separator: "/") + "/\(safeName).mbox"

            let entries = messages.map { raw in
                let sender = extractSender(from: raw.rawData)
                let date = extractDate(from: raw.rawData)
                return MBOXEntry(sender: sender, date: date, rawRFC2822: raw.rawData)
            }

            let data = MBOXWriter.write(messages: entries)
            result.append((filename, data))
        }
        return result
    }

    private func extractSender(from rawData: Data) -> String {
        guard let text = String(data: rawData, encoding: .utf8) else { return "unknown" }
        for line in text.components(separatedBy: "\r\n") {
            if line.isEmpty { break }  // End of headers
            if line.lowercased().hasPrefix("from:") {
                let value = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                // Extract email from "Name <email@example.com>" format
                if let start = value.lastIndex(of: "<"),
                    let end = value.lastIndex(of: ">") {
                    return String(value[value.index(after: start)..<end])
                }
                return value
            }
        }
        return "unknown"
    }

    private func extractDate(from rawData: Data) -> Date {
        guard let text = String(data: rawData, encoding: .utf8) else { return Date() }
        for line in text.components(separatedBy: "\r\n") {
            if line.isEmpty { break }
            if line.lowercased().hasPrefix("date:") {
                let value = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                return Self.rfc2822Formatter.date(from: value) ?? Date()
            }
        }
        return Date()
    }

    private static let rfc2822Formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HHmmss"
        return formatter
    }()
}
