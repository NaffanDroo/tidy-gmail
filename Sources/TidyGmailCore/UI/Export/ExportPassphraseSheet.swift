import SwiftUI

// MARK: - Export passphrase prompt sheet

@MainActor
struct ExportPassphraseSheet: View {
    @Environment(\.dismiss) private var dismiss
    let viewModel: EmailListViewModel
    let messageCount: Int

    @State private var passphrase: String = ""
    @State private var selectedDestination: URL?
    @State private var isShowingFileDialog = false
    @State private var validationState: PassphraseValidation?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "lock.doc")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("Export \(messageCount) email(s)")
                        .font(.headline)
                    Text("Choose a passphrase and save location")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)

                Divider()

                // Destination
                VStack(alignment: .leading, spacing: 8) {
                    Label("Save Location", systemImage: "folder")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if let dest = selectedDestination {
                        HStack {
                            Image(systemName: "doc.badge.checkmark")
                                .foregroundStyle(.green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(dest.lastPathComponent)
                                    .font(.callout)
                                Text(dest.deletingLastPathComponent().path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button("Change", action: { isShowingFileDialog = true })
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                        .padding(10)
                        .background(.background.secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        Button("Choose Folder", action: { isShowingFileDialog = true })
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .controlSize(.large)
                    }
                }

                // Passphrase
                VStack(alignment: .leading, spacing: 8) {
                    Label("Passphrase", systemImage: "key")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    SecureField("At least 12 characters", text: $passphrase)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: passphrase) {
                            validationState = PassphraseValidator.validate(passphrase)
                        }

                    if let validation = validationState {
                        VStack(alignment: .leading, spacing: 6) {
                            if !validation.isValid {
                                HStack(spacing: 6) {
                                    Image(systemName: "exclamationmark.circle")
                                        .foregroundStyle(.orange)
                                    Text(validation.message ?? "Invalid passphrase")
                                        .font(.caption)
                                }
                            } else {
                                HStack(spacing: 6) {
                                    Image(systemName: strengthIcon)
                                        .foregroundStyle(strengthColor)
                                    Text(validation.strength.label)
                                        .font(.caption)
                                        .foregroundStyle(strengthColor)
                                }
                                ProgressView(value: Double(validation.strength.rawValue), total: 3)
                                    .frame(height: 6)
                            }
                        }
                    }
                }

                Spacer()

                // Actions
                HStack(spacing: 12) {
                    Button("Cancel") { dismiss() }
                        .frame(maxWidth: .infinity)

                    Button("Export") {
                        guard let destination = selectedDestination else { return }
                        dismiss()
                        Task {
                            await viewModel.exportSelected(to: destination, passphrase: passphrase)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .disabled(selectedDestination == nil || !(validationState?.isValid ?? false))
                }
            }
            .padding(20)
            .navigationTitle("Export Emails")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .fileImporter(
            isPresented: $isShowingFileDialog,
            allowedContentTypes: [.folder],
            onCompletion: { result in
                if case .success(let url) = result {
                    selectedDestination = url
                }
            }
        )
    }

    private var strengthColor: Color {
        guard let validation = validationState else { return .secondary }
        switch validation.strength {
        case .weak: return .red
        case .fair: return .orange
        case .strong: return .yellow
        case .excellent: return .green
        }
    }

    private var strengthIcon: String {
        guard let validation = validationState else { return "xmark" }
        switch validation.strength {
        case .weak: return "checkmark.circle.fill"
        case .fair: return "checkmark.circle.fill"
        case .strong: return "checkmark.circle.fill"
        case .excellent: return "checkmark.circle.fill"
        }
    }
}

#Preview {
    struct Preview: View {
        @State private var viewModel = EmailListViewModel(
            client: LiveGmailAPIClient(tokenProvider: AppAuthOAuthManager()))
        var body: some View {
            ExportPassphraseSheet(viewModel: viewModel, messageCount: 10)
        }
    }
    return Preview()
}
