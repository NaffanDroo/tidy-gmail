import SwiftUI

@MainActor
public struct EmailListView: View {
    @State private var viewModel: EmailListViewModel?
    @State private var selectedMessage: GmailMessage?
    @State private var deletionTask: Task<Void, Never>?
    @Environment(AuthState.self) private var authState
    @Environment(AppAuthOAuthManager.self) private var oauthManager

    public init() {}

    public var body: some View {
        Group {
            if let viewModel {
                NavigationSplitView {
                    sidebarContent(viewModel: viewModel)
                } detail: {
                    if let selectedMessage {
                        EmailDetailView(message: selectedMessage)
                    } else {
                        ContentUnavailableView(
                            "No message selected",
                            systemImage: "envelope",
                            description: Text("Select an email from the list to preview it.")
                        )
                    }
                }
                .navigationTitle("Tidy Gmail")
                .toolbar { toolbarContent(viewModel: viewModel) }
                .sheet(isPresented: Bindable(viewModel).showTrashConfirmation) {
                    TrashConfirmationSheet(viewModel: viewModel, deletionTask: $deletionTask)
                }
                .overlay { deletionProgressOverlay(viewModel: viewModel) }
                .alert(
                    "Deletion Failed",
                    isPresented: Binding(
                        get: { viewModel.deleteError != nil },
                        set: { if !$0 { viewModel.deleteError = nil } }
                    ),
                    actions: { Button("OK") { viewModel.deleteError = nil } },
                    message: { Text(viewModel.deleteError?.userMessage ?? "") }
                )
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            if viewModel == nil {
                viewModel = EmailListViewModel(client: LiveGmailAPIClient(tokenProvider: oauthManager))
            }
        }
    }

    // MARK: - Sidebar

    private func sidebarContent(viewModel: EmailListViewModel) -> some View {
        VStack(spacing: 0) {
            searchBar(viewModel: viewModel)

            if viewModel.isLoading {
                loadingView
            } else if let error = viewModel.error {
                errorView(error)
            } else if viewModel.messages.isEmpty && !viewModel.searchText.isEmpty {
                emptyStateView
            } else {
                messageList(viewModel: viewModel)
            }
        }
    }

    private func searchBar(viewModel: EmailListViewModel) -> some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField("Search mail (Gmail syntax supported)", text: Bindable(viewModel).searchText)
                .textFieldStyle(.plain)
                .onSubmit { Task { await viewModel.search() } }
                .accessibilityLabel("Search emails")
        }
        .padding(10)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func messageList(viewModel: EmailListViewModel) -> some View {
        List {
            ForEach(viewModel.messages) { message in
                EmailRowView(
                    message: message,
                    isSelected: viewModel.selectedMessageIDs.contains(message.id),
                    onToggleSelect: {
                        if viewModel.selectedMessageIDs.contains(message.id) {
                            viewModel.selectedMessageIDs.remove(message.id)
                        } else {
                            viewModel.selectedMessageIDs.insert(message.id)
                        }
                    },
                    onTap: { selectedMessage = message }
                )
                .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 12))
                .listRowSeparator(.visible)
            }

            if viewModel.hasMorePages {
                loadMoreButton(viewModel: viewModel)
            }
        }
        .listStyle(.plain)
        .accessibilityLabel("Email list, \(viewModel.messages.count) messages")
    }

    private func loadMoreButton(viewModel: EmailListViewModel) -> some View {
        HStack {
            Spacer()
            Button("Load more") { Task { await viewModel.loadNextPage() } }
                .buttonStyle(.borderless)
                .disabled(viewModel.isLoadingMore)
            if viewModel.isLoadingMore {
                ProgressView().controlSize(.small)
            }
            Spacer()
        }
        .listRowSeparator(.hidden)
        .padding(.vertical, 8)
    }

    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView("Searching…")
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Loading results")
    }

    private func errorView(_ error: GmailAPIError) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.title)
                .foregroundStyle(.red)
                .accessibilityHidden(true)
            Text(error.userMessage)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
        .accessibilityLabel("Error: \(error.userMessage)")
    }

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "tray")
                .font(.title)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("No messages found")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .accessibilityLabel("No messages found for your search")
    }

    // MARK: - Deletion progress overlay

    @ViewBuilder
    private func deletionProgressOverlay(viewModel: EmailListViewModel) -> some View {
        if viewModel.isDeleting {
            ZStack {
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
                VStack(spacing: 16) {
                    ProgressView(value: viewModel.deleteProgress)
                        .progressViewStyle(.linear)
                        .frame(width: 240)
                    Text(viewModel.deleteProgress < 1.0 ? "Moving to Trash…" : "Done")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                    Button("Cancel") {
                        deletionTask?.cancel()
                        deletionTask = nil
                    }
                    .buttonStyle(.bordered)
                    .help("Cancel — emails already moved to Trash will remain there")
                }
                .padding(28)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(radius: 12)
            }
            .accessibilityLabel("Moving emails to Trash, \(Int(viewModel.deleteProgress * 100)) percent complete")
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private func toolbarContent(viewModel: EmailListViewModel) -> some ToolbarContent {
        if !viewModel.messages.isEmpty {
            ToolbarItem(placement: .automatic) {
                selectionCountLabel(viewModel: viewModel)
            }

            ToolbarItem(placement: .automatic) {
                let allSelected = viewModel.selectedMessageIDs.count == viewModel.messages.count
                Button {
                    if allSelected { viewModel.clearSelection() } else { viewModel.selectAll() }
                } label: {
                    Label(
                        allSelected ? "Deselect All" : "Select All",
                        systemImage: allSelected ? "checkmark.circle.fill" : "checkmark.circle"
                    )
                }
                .keyboardShortcut("a", modifiers: .command)
                .help(allSelected ? "Deselect all (⌘A)" : "Select all (⌘A)")
            }

            ToolbarItem(placement: .automatic) {
                Button {
                    viewModel.showTrashConfirmation = true
                } label: {
                    Label("Move to Trash", systemImage: "trash")
                }
                .disabled(viewModel.selectedMessageIDs.isEmpty)
                .help("Move selected emails to Trash. To permanently delete, empty Trash in Gmail.")
            }
        }

        ToolbarItem(placement: .automatic) {
            Button("Sign out") {
                try? oauthManager.signOut()
                authState.isSignedIn = false
                authState.userEmail = nil
            }
            .help("Sign out of your Google account")
        }
    }

    @ViewBuilder
    private func selectionCountLabel(viewModel: EmailListViewModel) -> some View {
        let count = viewModel.selectedMessageIDs.count
        if count > 0 {
            Text("\(count) selected")
                .font(.callout)
                .foregroundStyle(.secondary)
                .accessibilityLabel("\(count) emails selected")
        }
    }
}

// MARK: - Email row

private struct EmailRowView: View {
    let message: GmailMessage
    let isSelected: Bool
    let onToggleSelect: () -> Void
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Toggle(isOn: Binding(get: { isSelected }, set: { _ in onToggleSelect() }), label: {
                EmptyView()
            })
            .toggleStyle(.checkbox)
            .accessibilityLabel(isSelected ? "Deselect \(message.subject)" : "Select \(message.subject)")

            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(message.from)
                            .font(.headline)
                            .lineLimit(1)
                        Spacer()
                        Text(message.date, style: .date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(message.subject.isEmpty ? "(No subject)" : message.subject)
                        .font(.subheadline)
                        .lineLimit(1)
                        .foregroundStyle(message.subject.isEmpty ? .secondary : .primary)

                    HStack {
                        Text(message.snippet)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Text(message.formattedSize)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            // swiftlint:disable:next line_length
            .accessibilityLabel("\(message.from), \(message.subject), \(message.date.formatted(date: .abbreviated, time: .omitted)), \(message.formattedSize)")
        }
    }
}

// MARK: - Trash confirmation sheet

private struct TrashConfirmationSheet: View {
    let viewModel: EmailListViewModel
    @Binding var deletionTask: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Move to Trash")
                .font(.title2)
                .bold()

            Text(countDescription)
                .fixedSize(horizontal: false, vertical: true)

            sampleSubjects

            // Permanent-deletion policy — shown prominently so users know what to expect.
            GroupBox {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.blue)
                        .accessibilityHidden(true)
                    Text(EmailListViewModel.permanentDeletionNote)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text("Emails in Trash are automatically purged by Gmail after 30 days. You can restore them before then.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.escape)
                Button("Move to Trash") {
                    dismiss()
                    deletionTask = Task { await viewModel.trashSelected() }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .keyboardShortcut(.return)
                .accessibilityLabel("Confirm move to Trash")
            }
        }
        .padding(24)
        .frame(minWidth: 420, maxWidth: 560)
    }

    private var countDescription: String {
        let count = viewModel.selectedMessageIDs.count
        return "\(count) email\(count == 1 ? "" : "s") will be moved to Trash."
    }

    @ViewBuilder
    private var sampleSubjects: some View {
        let samples = viewModel.selectedMessages.prefix(5)
        if !samples.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(samples)) { message in
                    Label(
                        message.subject.isEmpty ? "(No subject)" : message.subject,
                        systemImage: "envelope"
                    )
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                    .font(.callout)
                }
                if viewModel.selectedMessages.count > 5 {
                    Text("…and \(viewModel.selectedMessages.count - 5) more.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
            }
        }
    }
}

// MARK: - Error user messages

private extension GmailAPIError {
    var userMessage: String {
        switch self {
        case .unauthorized:
            return "Your session has expired. Please sign out and sign in again."
        case .rateLimited:
            return "Too many requests. Please wait a moment and try again."
        case .serverError(let code):
            return "Gmail returned an error (HTTP \(code)). Please try again."
        case .decodingFailed, .invalidResponse:
            return "Received an unexpected response from Gmail. Please try again."
        }
    }
}
