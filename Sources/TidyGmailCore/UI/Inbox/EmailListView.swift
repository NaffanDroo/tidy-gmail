import SwiftUI

@MainActor
public struct EmailListView: View {
    @State private var viewModel = EmailListViewModel()
    @Environment(AuthState.self) private var authState

    public init() {}

    public var body: some View {
        NavigationSplitView {
            sidebarContent
        } detail: {
            Text("Select an email to preview")
                .foregroundStyle(.secondary)
        }
        .navigationTitle("Tidy Gmail")
        .toolbar { toolbarContent }
    }

    // MARK: - Subviews

    private var sidebarContent: some View {
        VStack(spacing: 0) {
            searchBar

            if viewModel.isLoading {
                loadingView
            } else if let error = viewModel.error {
                errorView(error)
            } else if viewModel.messages.isEmpty && !viewModel.searchText.isEmpty {
                emptyStateView
            } else {
                messageList
            }
        }
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField("Search mail (Gmail syntax supported)", text: $viewModel.searchText)
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

    private var messageList: some View {
        List {
            ForEach(viewModel.messages) { message in
                EmailRowView(message: message)
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
            }

            if viewModel.hasMorePages {
                loadMoreButton
            }
        }
        .listStyle(.plain)
        .accessibilityLabel("Email list, \(viewModel.messages.count) messages")
    }

    private var loadMoreButton: some View {
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

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            Button("Sign out") { /* handled by AuthCoordinator */ }
                .help("Sign out of your Google account")
        }
    }
}

// MARK: - Email row

private struct EmailRowView: View {
    let message: GmailMessage

    var body: some View {
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(message.from), \(message.subject), \(message.date.formatted(date: .abbreviated, time: .omitted)), \(message.formattedSize)")
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
