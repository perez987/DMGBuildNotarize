import SwiftUI

struct StageListView: View {
    @Environment(\.colorScheme) private var colorScheme
    let stages: [StageProgress]

    var body: some View {
        List(stages) { progress in
            HStack(spacing: 10) {
                Image(systemName: symbol(for: progress.state))
                    .foregroundStyle(color(for: progress.state))
                    .frame(width: 18)

                Text(progress.stage.title)
                    .foregroundColor(Color(nsColor: .labelColor))
                    .lineLimit(1)

                Spacer()
            }
            .padding(.vertical, 3)
            .listRowBackground(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AppTheme.logBackground(for: colorScheme).opacity(0.35))
                    .padding(.vertical, 2)
                    .padding(.horizontal, 6)
            )
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .glassCard(colorScheme: colorScheme, cornerRadius: 20, accentOpacity: 0.16)
    }

    private func symbol(for state: StageState) -> String {
        switch state {
        case .pending: return "circle"
        case .running: return "circle.dotted"
        case .succeeded: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    private func color(for state: StageState) -> Color {
        switch state {
        case .pending: return .secondary
        case .running: return .accentColor
        case .succeeded: return .green
        case .failed: return .red
        }
    }
}
