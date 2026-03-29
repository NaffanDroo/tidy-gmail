import SwiftUI

// MARK: - Export summary sheet

@MainActor
struct ExportSummarySheet: View {
    @Environment(\.dismiss) private var dismiss
    let summary: ExportSummary

    @State private var isVerifying = false
    @State private var verificationMessage: String?
    @State private var verificationError: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Success header
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.green)
                    Text("Export Complete")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)

                Divider()

                // Summary details
                VStack(alignment: .leading, spacing: 16) {
                    SummaryRow(
                        label: "File",
                        value: summary.filePath.lastPathComponent,
                        icon: "doc.badge.checkmark"
                    )
                    Divider()

                    SummaryRow(
                        label: "Location",
                        value: summary.filePath.deletingLastPathComponent().path,
                        icon: "folder"
                    )
                    Divider()

                    SummaryRow(
                        label: "Size",
                        value: summary.formattedSize,
                        icon: "internaldrive"
                    )
                    Divider()

                    SummaryRow(
                        label: "Emails",
                        value: "\(summary.messageCount)",
                        icon: "envelope"
                    )
                }
                .padding(12)
                .background(.background.secondary)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                if let message = verificationMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text(message)
                            .font(.callout)
                    }
                    .padding(12)
                    .background(Color.green.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                if let error = verificationError {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                        Text(error)
                            .font(.callout)
                    }
                    .padding(12)
                    .background(Color.red.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                Spacer()

                // Actions
                VStack(spacing: 10) {
                    Button(
                        action: { Task { await verifyExport() } },
                        label: {
                            Label("Verify Archive", systemImage: "checkmark.seal.fill")
                                .frame(maxWidth: .infinity)
                        }
                    )
                    .buttonStyle(.bordered)
                    .disabled(isVerifying)

                    if isVerifying {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Button("Done") { dismiss() }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(20)
            .navigationTitle("Export Complete")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func verifyExport() async {
        isVerifying = true
        verificationError = nil
        verificationMessage = nil
        defer { isVerifying = false }

        do {
            // Mount the DMG read-only
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            process.arguments = ["attach", "-readonly", summary.filePath.path]
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                verificationError = "Failed to mount DMG"
                return
            }

            verificationMessage = "✓ Archive integrity verified. DMG mounted successfully."
        } catch {
            verificationError = "Verification failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Summary row component

private struct SummaryRow: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.callout)
                    .lineLimit(1)
            }
            Spacer()
        }
    }
}

#Preview {
    ExportSummarySheet(
        summary: ExportSummary(
            filePath: URL(fileURLWithPath: "/Users/nathan/Desktop/TidyGmail-Export.dmg"),
            fileSize: 52_428_800,
            messageCount: 42
        )
    )
}
