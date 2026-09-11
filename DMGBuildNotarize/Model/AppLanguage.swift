import Foundation

struct AppLanguage: Identifiable, Equatable {
    let code: String
    let nativeName: String
    let flag: String

    var id: String { code }

    static let supported: [AppLanguage] = [
        AppLanguage(code: "en", nativeName: "English", flag: "🇬🇧"),
        AppLanguage(code: "es", nativeName: "Español", flag: "🇪🇸"),
        AppLanguage(code: "de", nativeName: "Deutsch", flag: "🇩🇪"),
        AppLanguage(code: "fr", nativeName: "Français", flag: "🇫🇷"),
        AppLanguage(code: "it", nativeName: "Italiano", flag: "🇮🇹"),
    ]

    static let defaultLanguage = supported[0]

    static func resolve(code: String) -> AppLanguage {
        let normalizedCode = code.components(separatedBy: "-").first?.lowercased() ?? defaultLanguage.code
        return supported.first { $0.code == normalizedCode } ?? defaultLanguage
    }
}
