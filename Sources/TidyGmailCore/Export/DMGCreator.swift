import Foundation

// MARK: - Protocol

public protocol DMGCreator: Sendable {
    /// Create an AES-256 encrypted DMG from a source directory.
    /// Passphrase is passed via stdin to `hdiutil` — never as a CLI argument.
    func createEncryptedDMG(
        sourceDirectory: URL,
        destination: URL,
        volumeName: String,
        passphrase: String
    ) async throws

    /// Mount a DMG read-only for verification. Returns the mount point URL.
    func mountReadOnly(dmgPath: URL, passphrase: String) async throws -> URL

    /// Unmount a previously mounted volume.
    func unmount(volumePath: URL) async throws
}

// MARK: - Live implementation

public final class LiveDMGCreator: DMGCreator {
    public init() {}

    public func createEncryptedDMG(
        sourceDirectory: URL,
        destination: URL,
        volumeName: String,
        passphrase: String
    ) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = [
            "create",
            "-srcfolder", sourceDirectory.path,
            "-encryption", "AES-256",
            "-stdinpass",
            "-volname", volumeName,
            "-fs", "HFS+",
            "-format", "UDBZ",
            destination.path
        ]

        let stdinPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardError = stderrPipe
        process.standardOutput = FileHandle.nullDevice

        try process.run()

        // Write passphrase to stdin and close — hdiutil reads it from there
        let passphraseData = Data(passphrase.utf8)
        stdinPipe.fileHandleForWriting.write(passphraseData)
        stdinPipe.fileHandleForWriting.closeFile()

        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrString = String(data: stderrData, encoding: .utf8) ?? "Unknown error"
            throw ExportError.dmgCreationFailed(
                stderrString.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    public func mountReadOnly(dmgPath: URL, passphrase: String) async throws -> URL {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = [
            "attach",
            dmgPath.path,
            "-readonly",
            "-stdinpass",
            "-nobrowse",
            "-plist"
        ]

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        stdinPipe.fileHandleForWriting.write(Data(passphrase.utf8))
        stdinPipe.fileHandleForWriting.closeFile()

        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrString = String(data: stderrData, encoding: .utf8) ?? "Unknown error"
            let trimmedError = stderrString.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ExportError.dmgCreationFailed("Mount failed: \(trimmedError)")
        }

        let outputData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        guard
            let plist = try? PropertyListSerialization.propertyList(from: outputData, format: nil)
                as? [String: Any],
            let entities = plist["system-entities"] as? [[String: Any]],
            let mountPoint = entities.first(where: { $0["mount-point"] != nil })?["mount-point"]
                as? String
        else {
            throw ExportError.dmgCreationFailed("Could not determine mount point")
        }

        return URL(fileURLWithPath: mountPoint)
    }

    public func unmount(volumePath: URL) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["detach", volumePath.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()
    }
}
