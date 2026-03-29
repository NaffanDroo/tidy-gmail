import SwiftUI

// MARK: - Email row

struct EmailRowView: View {
    let message: GmailMessage
    let isSelected: Bool
    let onToggleSelect: () -> Void
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Toggle(
                isOn: Binding(get: { isSelected }, set: { _ in onToggleSelect() }),
                label: {
                    EmptyView()
                }
            )
            .toggleStyle(.checkbox)
            .accessibilityLabel(
                isSelected ? "Deselect \(message.subject)" : "Select \(message.subject)")

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
            .accessibilityLabel(
                "\(message.from), \(message.subject), "
                + "\(message.date.formatted(date: .abbreviated, time: .omitted)), \(message.formattedSize)"
            )
        }
    }
}

// MARK: - Trash confirmation sheet

struct TrashConfirmationSheet: View {
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

            Text(
                "Emails in Trash are automatically purged by Gmail after 30 days. "
                + "You can restore them before then."
            )
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
