import SwiftUI

// MARK: - View

@MainActor
public struct LabelAnalysisView: View {
    @State private var viewModel: LabelAnalysisViewModel
    @State private var analysisTask: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss

    /// Called when the user taps a label row. Receives the selected `LabelStat`.
    /// The view dismisses itself after invoking this callback.
    let onSelectLabel: (LabelStat) -> Void

    public init(client: any GmailAPIClient, onSelectLabel: @escaping (LabelStat) -> Void) {
        self._viewModel = State(initialValue: LabelAnalysisViewModel(client: client))
        self.onSelectLabel = onSelectLabel
    }

    public var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                mainContent
                if viewModel.scanState == .scanning {
                    progressBar
                }
            }
            .navigationTitle("Label Analysis")
            .toolbar { toolbarContent }
        }
        .task {
            // Auto-start on first appearance.
            if viewModel.scanState == .idle {
                analysisTask = Task { await viewModel.startAnalysis() }
            }
        }
        .frame(minWidth: 480, minHeight: 360)
    }

    // MARK: - Main content

    @ViewBuilder
    private var mainContent: some View {
        if !viewModel.stats.isEmpty {
            statsList
        } else {
            switch viewModel.scanState {
            case .idle:
                startPrompt
            case .scanning:
                fetchingPlaceholder
            case .complete:
                emptyStateView
            case .failed(let message):
                failedView(message: message)
            }
        }
    }

    private var statsList: some View {
        List(viewModel.stats) { stat in
            LabelStatRow(stat: stat)
                .contentShape(Rectangle())
                .onTapGesture {
                    onSelectLabel(stat)
                    dismiss()
                }
                .accessibilityAddTraits(.isButton)
        }
        .listStyle(.plain)
        .accessibilityLabel("Labels ranked by storage, \(viewModel.stats.count) labels")
    }

    private var fetchingPlaceholder: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView("Fetching labels\u{2026}")
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Fetching label information")
    }

    private var startPrompt: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.xaxis")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("See which labels consume the most storage")
                .foregroundStyle(.secondary)
            Button("Start Analysis") {
                analysisTask = Task { await viewModel.startAnalysis() }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.title)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("No labels found")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("No labels found")
    }

    private func failedView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.red)
                .accessibilityHidden(true)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            Button("Retry") {
                analysisTask = Task { await viewModel.startAnalysis() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("Analysis failed: \(message)")
    }

    // MARK: - Progress bar (shown at bottom while scanning)

    private var progressBar: some View {
        VStack(spacing: 6) {
            if viewModel.totalMessages > 0 {
                ProgressView(
                    value: Double(viewModel.scannedCount),
                    total: Double(viewModel.totalMessages)
                )
                .progressViewStyle(.linear)
                .padding(.horizontal, 16)
                .accessibilityLabel(
                    "Scanning, \(viewModel.scannedCount) of \(viewModel.totalMessages) messages")
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
                    .padding(.horizontal, 16)
            }
            HStack {
                if viewModel.totalMessages > 0 {
                    Text("\(viewModel.scannedCount) / \(viewModel.totalMessages) messages scanned")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer()
                Button("Cancel") {
                    analysisTask?.cancel()
                    analysisTask = nil
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .help("Cancel the analysis")
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Close") {
                analysisTask?.cancel()
                dismiss()
            }
            .keyboardShortcut(.escape)
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                analysisTask = Task { await viewModel.startAnalysis() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(viewModel.scanState == .scanning)
            .help("Re-run the label analysis")
        }
    }
}

// MARK: - Label stat row

private struct LabelStatRow: View {
    let stat: LabelStat

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(stat.name)
                    .font(.body)
                Text(
                    stat.messageCount == 1
                        ? "1 message"
                        : "\(stat.messageCount) messages"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text(stat.formattedSize)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(stat.name), \(stat.messageCount) messages, \(stat.formattedSize)")
        .accessibilityHint("Tap to filter email list to this label")
    }
}
