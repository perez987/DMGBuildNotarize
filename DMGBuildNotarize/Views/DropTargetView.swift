import SwiftUI
import UniformTypeIdentifiers

struct DropTargetView: View {
    let isInspecting: Bool
    let onAppURL: (URL) -> Void
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: isInspecting ? "magnifyingglass" : "app.dashed")
                .font(.system(size: 42, weight: .regular))
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)

            Text(isInspecting ? "Inspecting App" : "Drop Signed App")
                .font(.headline)

            Text(".app bundle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 180)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(isTargeted ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isTargeted ? Color.accentColor : Color.secondary.opacity(0.25), style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isTargeted) { providers in
            loadFirstURL(from: providers)
        }
    }

    private func loadFirstURL(from providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        _ = provider.loadObject(ofClass: URL.self) { item, _ in
            if let url = item {
                Task { @MainActor in onAppURL(url) }
            }
        }

        return true
    }
}
