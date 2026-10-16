import SwiftUI
import UniformTypeIdentifiers

struct DropTargetView: View {
    @Environment(\.colorScheme) private var colorScheme
    let isInspecting: Bool
    let onAppURL: (URL) -> Void
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: isInspecting ? "magnifyingglass" : "app.dashed")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(isTargeted ? AnyShapeStyle(AppTheme.accentGradient) : AnyShapeStyle(.secondary))

            Text(isInspecting ? "Inspecting App" : "Drop Signed App")
                .font(.headline.weight(.semibold))

            Text(".app bundle")
                .font(.caption)
                .foregroundStyle(.secondary.opacity(0.92))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 180)
        .glassCard(colorScheme: colorScheme, cornerRadius: 20, accentOpacity: 0.26)
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppTheme.accentGlow(for: colorScheme))
                .opacity(isTargeted ? (colorScheme == .dark ? 0.55 : 0.95) : (colorScheme == .dark ? 0.18 : 0.42))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    isTargeted ? AppTheme.accentGradient : AppTheme.borderGradient(for: colorScheme),
                    style: StrokeStyle(lineWidth: isTargeted ? 2 : 1.5, dash: [9, 6])
                )
        }
        .shadow(color: AppTheme.shadowColor(for: colorScheme), radius: 10, x: 0, y: 6)
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: isTargeted)
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
