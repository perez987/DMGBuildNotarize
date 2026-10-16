import Foundation

struct SigningIdentity: Identifiable, Hashable {
    var id: String { hash }

    let hash: String
    let name: String

    var displayName: String {
        "\(name) (\(hash.prefix(10)))"
    }

    var teamID: String? {
        Self.extractTeamID(from: name)
    }

    static func extractTeamID(from identityName: String) -> String? {
        guard let open = identityName.lastIndex(of: "("),
              let close = identityName.lastIndex(of: ")"),
              open < close
        else {
            return nil
        }

        let candidate = identityName[identityName.index(after: open)..<close]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return candidate.isEmpty ? nil : candidate
    }
}
