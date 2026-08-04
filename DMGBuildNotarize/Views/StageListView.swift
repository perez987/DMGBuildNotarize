import SwiftUI

struct StageListView: View {
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
        }
        .listStyle(.inset)
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
