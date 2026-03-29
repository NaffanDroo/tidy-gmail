import SwiftUI

// MARK: - Export progress overlay

@MainActor
struct ExportProgressOverlay: View {
    let progress: ExportProgress
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.25)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView(value: progress.fraction)
                    .progressViewStyle(.linear)
                    .frame(width: 240)
                
                VStack(spacing: 4) {
                    Text(progress.description)
                        .font(.callout)
                        .foregroundStyle(.primary)
                    HStack(spacing: 4) {
                        Text("\(progress.current)")
                            .monospacedDigit()
                        Text("of")
                        Text("\(progress.total)")
                            .monospacedDigit()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.bordered)
                .help("Cancel export — incomplete DMG will be deleted")
            }
            .padding(28)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(radius: 12)
        }
        .accessibilityLabel("Exporting emails, \(Int(progress.fraction * 100)) percent complete")
    }
}

#Preview {
    ExportProgressOverlay(
        progress: ExportProgress(phase: .fetchingMessages, current: 5, total: 10),
        onCancel: {}
    )
}
