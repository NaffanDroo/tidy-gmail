import SwiftUI

@MainActor
struct EmailDetailView: View {
    let message: GmailMessage

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                headerSection
                Divider()
                bodySection
            }
        }
        .navigationTitle(message.subject.isEmpty ? "(No subject)" : message.subject)
        .navigationSubtitle(message.from)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(message.subject.isEmpty ? "(No subject)" : message.subject)
                .font(.title2.bold())
                .textSelection(.enabled)

            Divider()

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    Text("From")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.trailing)

                    Text(message.from)
                        .font(.subheadline)
                        .textSelection(.enabled)
                }

                GridRow {
                    Text("Date")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text(message.date, format: .dateTime.weekday(.wide).month(.wide).day().hour().minute())
                        .font(.subheadline)
                }

                GridRow {
                    Text("Size")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text(message.formattedSize)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary)
    }

    // MARK: - Body

    private var bodySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if message.snippet.isEmpty {
                Text("No preview available.")
                    .foregroundStyle(.secondary)
                    .italic()
            } else {
                Text(message.snippet)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
    }
}
