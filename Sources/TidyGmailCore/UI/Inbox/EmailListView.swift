import SwiftUI

@MainActor
public struct EmailListView: View {
    @State private var viewModel: EmailListViewModel?
    @State private var selectedMessage: GmailMessage?
    @State private var deletionTask: Task<Void, Never>?
    @State private var exportTask: Task<Void, Never>?
    @Environment(AuthState.self) private var authState
    @Environment(AppAuthOAuthManager.self) private var oauthManager

    public init() {}

    public var body: some View {
        Group {
            if let viewModel {
                innerContent(viewModel: viewModel)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            if viewModel == nil {
                viewModel = EmailListViewModel(
                    client: LiveGmailAPIClient(tokenProvider: oauthManager))
            }
        }
    }

    @ViewBuilder
    private func innerContent(viewModel: EmailListViewModel) -> some View {
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
        .sheet(isPresented: Bindable(viewModel).showExportPrompt) {
            let count = viewModel.selectedMessageIDs.count
            if count > 0 {
                ExportPassphraseSheet(viewModel: viewModel, messageCount: count)
            }
        }
        .sheet(item: Bindable(viewModel).exportSummary) { summary in
            ExportSummarySheet(summary: summary)
        }
        .overlay { deletionProgressOverlay(viewModel: viewModel) }
        .overlay { exportProgressOverlay(viewModel: viewModel, exportTask: $exportTask) }
        .alert(
            "Deletion Failed",
            isPresented: Binding(
                get: { viewModel.deleteError != nil },
                set: { if !$0 { viewModel.deleteError = nil } }
            ),
            actions: { Button("OK") { viewModel.deleteError = nil } },
            message: { Text(viewModel.deleteError?.userMessage ?? "") }
        )
        .alert(
            "Export Failed",
            isPresented: Binding(
                get: { viewModel.exportError != nil },
                set: { if !$0 { viewModel.exportError = nil } }
            ),
            actions: { Button("OK") { viewModel.exportError = nil } },
            message: {
                if let error = viewModel.exportError {
                    Text(error.localizedDescription)
                }
            }
        )
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
            .accessibilityLabel(
                "Moving emails to Trash, \(Int(viewModel.deleteProgress * 100)) percent complete")
        }
    }

    @ViewBuilder
    private func exportProgressOverlay(
        viewModel: EmailListViewModel, exportTask: Binding<Task<Void, Never>?>
    ) -> some View {
        if viewModel.isExporting, let progress = viewModel.exportProgress {
            ExportProgressOverlay(
                progress: progress,
                onCancel: {
                    exportTask.wrappedValue?.cancel()
                    exportTask.wrappedValue = nil
                }
            )
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

            ToolbarItem(placement: .automatic) {
                Button {
                    viewModel.showExportPrompt = true
                } label: {
                    Label("Export", systemImage: "arrow.up.doc")
                }
                .disabled(viewModel.selectedMessageIDs.isEmpty)
                .help("Export selected emails to an encrypted DMG archive")
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

// MARK: - Email row is extracted to EmailListViewHelpers.swift
