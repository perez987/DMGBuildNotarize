import SwiftUI

enum AppTheme {
    static let accentGradient = LinearGradient(
        colors: [
            Color(red: 0.25, green: 0.55, blue: 0.98),
            Color(red: 0.50, green: 0.43, blue: 0.95),
            Color(red: 0.89, green: 0.49, blue: 0.76),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static func windowGradient(for colorScheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    Color(red: 0.09, green: 0.11, blue: 0.14),
                    Color(red: 0.12, green: 0.13, blue: 0.18),
                    Color(red: 0.09, green: 0.10, blue: 0.14),
                ]
                : [
                    Color(red: 0.95, green: 0.97, blue: 1.0),
                    Color(red: 0.94, green: 0.93, blue: 1.0),
                    Color(red: 0.89, green: 0.96, blue: 0.98),
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func cardMaterial(for colorScheme: ColorScheme) -> Material {
        colorScheme == .dark ? .regularMaterial : .ultraThinMaterial
    }

    static func surfaceGradient(for colorScheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    Color(red: 0.20, green: 0.21, blue: 0.26).opacity(0.86),
                    Color(red: 0.14, green: 0.15, blue: 0.20).opacity(0.76),
                ]
                : [
                    Color.white.opacity(0.55),
                    Color.white.opacity(0.16),
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func raisedSurfaceFill(for colorScheme: ColorScheme, emphasized: Bool = false) -> LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? emphasized
                    ? [
                        Color(red: 0.22, green: 0.26, blue: 0.38).opacity(0.94),
                        Color(red: 0.17, green: 0.19, blue: 0.29).opacity(0.84),
                    ]
                    : [
                        Color.white.opacity(0.10),
                        Color.white.opacity(0.04),
                    ]
                : emphasized
                    ? [
                        Color.white.opacity(0.92),
                        Color(red: 0.88, green: 0.93, blue: 1.0).opacity(0.9),
                    ]
                    : [
                        Color.white.opacity(0.74),
                        Color.white.opacity(0.30),
                    ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func surfaceHighlight(for colorScheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color.white.opacity(0.12), Color.white.opacity(0.03)]
                : [Color.white.opacity(0.24), Color.white.opacity(0.06)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func borderGradient(for colorScheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color.white.opacity(0.24), Color.white.opacity(0.10)]
                : [Color.white.opacity(0.84), Color.white.opacity(0.25)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func accentGlow(for colorScheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    Color(red: 0.25, green: 0.55, blue: 0.98).opacity(0.14),
                    Color(red: 0.50, green: 0.43, blue: 0.95).opacity(0.10),
                    Color(red: 0.89, green: 0.49, blue: 0.76).opacity(0.08),
                ]
                : [
                    Color(red: 0.25, green: 0.55, blue: 0.98).opacity(0.30),
                    Color(red: 0.50, green: 0.43, blue: 0.95).opacity(0.22),
                    Color(red: 0.89, green: 0.49, blue: 0.76).opacity(0.18),
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func shadowColor(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.black.opacity(0.52) : Color.black.opacity(0.12)
    }

    static func logBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.09, green: 0.10, blue: 0.13).opacity(0.92)
            : Color.white.opacity(0.22)
    }
}

extension View {
    func glassCard(
        colorScheme: ColorScheme,
        cornerRadius: CGFloat = 22,
        accentOpacity: Double = 0.2
    ) -> some View {
        background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(AppTheme.cardMaterial(for: colorScheme))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(AppTheme.surfaceGradient(for: colorScheme))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(AppTheme.surfaceHighlight(for: colorScheme))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(AppTheme.accentGlow(for: colorScheme))
                        .opacity(colorScheme == .dark ? accentOpacity * 0.6 : accentOpacity)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(AppTheme.borderGradient(for: colorScheme), lineWidth: 1)
                }
                .shadow(color: AppTheme.shadowColor(for: colorScheme), radius: 16, x: 0, y: 10)
        }
    }
}
