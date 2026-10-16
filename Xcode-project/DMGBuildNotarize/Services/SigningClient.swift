import Foundation

struct SigningClient: Sendable {
    let runner: any ProcessRunning

    nonisolated init(runner: any ProcessRunning = ProcessRunner()) {
        self.runner = runner
    }

    func loadDeveloperIDApplicationIdentities() async throws -> [SigningIdentity] {
        let result = try await runner.run(.system("/usr/bin/security", ["find-identity", "-p", "codesigning", "-v"]), onOutput: { _ in })
        return Self.parseDeveloperIDApplicationIdentities(result.combinedOutput)
    }

    func signDMG(_ dmgURL: URL, identity: SigningIdentity, onOutput: @escaping @Sendable (String) -> Void = { _ in }) async throws {
        try await runner.run(
            .system("/usr/bin/codesign", ["--force", "--sign", identity.hash, dmgURL.path]),
            onOutput: onOutput
        )
    }

    static func parseDeveloperIDApplicationIdentities(_ output: String) -> [SigningIdentity] {
        output
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> SigningIdentity? in
                let text = String(line)
                guard text.contains("Developer ID Application:") else { return nil }
                guard let firstQuote = text.firstIndex(of: "\""),
                      let lastQuote = text.lastIndex(of: "\""),
                      firstQuote < lastQuote
                else { return nil }

                let prefix = text[..<firstQuote].split(separator: " ")
                guard let hash = prefix.last else { return nil }

                let name = String(text[text.index(after: firstQuote)..<lastQuote])
                return SigningIdentity(hash: String(hash), name: name)
            }
    }
}
