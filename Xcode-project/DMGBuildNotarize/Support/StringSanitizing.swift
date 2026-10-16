import Foundation

extension String {
    var sanitizedFileComponent: String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>").union(.newlines).union(.controlCharacters)
        let pieces = components(separatedBy: invalid).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let joined = pieces.filter { !$0.isEmpty }.joined(separator: "-")
        return joined.isEmpty ? "Installer" : joined
    }

    func sanitizedVolumeName(defaultValue: String) -> String {
        let invalid = CharacterSet(charactersIn: ":/").union(.newlines).union(.controlCharacters)
        let sanitized = components(separatedBy: invalid)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if sanitized.isEmpty {
            return defaultValue
        }

        return String(sanitized.prefix(27))
    }

    var shellSingleQuoted: String {
        "'\(replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    var removingNewlines: String {
        components(separatedBy: .newlines).joined()
    }
}
