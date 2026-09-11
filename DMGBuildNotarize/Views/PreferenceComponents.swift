import SwiftUI

struct PreferenceCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let accentOpacity: Double
    let content: Content

    init(accentOpacity: Double = 0.18, @ViewBuilder content: () -> Content) {
        self.accentOpacity = accentOpacity
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            content
        }
        .padding(18)
        .glassCard(colorScheme: colorScheme, cornerRadius: 22, accentOpacity: accentOpacity)
    }
}

struct PreferenceSectionHeader: View {
    let title: LocalizedStringKey
    let systemImage: String
    let subtitle: String?

    init(_ title: LocalizedStringKey, systemImage: String, subtitle: String? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(title)
                    .font(.headline.weight(.semibold))
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(AppTheme.accentGradient)
            }

            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct PreferenceField<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: LocalizedStringKey
    let content: Content

    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            content
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(AppTheme.raisedSurfaceFill(for: colorScheme))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(AppTheme.borderGradient(for: colorScheme), lineWidth: 1)
                        }
                }
        }
    }
}
