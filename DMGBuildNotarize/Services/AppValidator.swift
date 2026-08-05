import Foundation

struct AppValidator: Sendable {
    let runner: any ProcessRunning

    init(runner: any ProcessRunning = ProcessRunner()) {
        self.runner = runner
    }

    func validate(appURL: URL, onOutput: @escaping @Sendable (String) -> Void = { _ in }) async throws -> ValidationReport {
        let info = try AppBundleInfo.load(from: appURL)

        onOutput(String(localized: "Checking code signature…\n"))

        let verifyResult = try await runner.run(
            .system("/usr/bin/codesign", ["--verify", "--deep", "--strict", "--verbose=2", appURL.path]),
            onOutput: { _ in }
        )

        onOutput(String(localized: "Reading signing certificate details…\n"))

        let detailsResult = try await runner.run(
            .system("/usr/bin/codesign", ["-dv", "--verbose=4", appURL.path]),
            onOutput: { _ in }
        )

        let details = detailsResult.combinedOutput
        guard Self.isDistributionReadySignature(details) else {
            let authority = Self.firstMatch(in: details, prefix: "Authority=") ?? ""
            throw AppValidationError.notDistributionSigned(authority)
        }

        onOutput(String(localized: "Checking Gatekeeper acceptance…\n"))

        let gatekeeperResult = try await runner.run(
            .system("/usr/sbin/spctl", ["-a", "-vv", "-t", "execute", appURL.path]),
            onOutput: { _ in }
        )

        onOutput(Self.makeSummary(info: info, details: details, gatekeeperOutput: gatekeeperResult.combinedOutput))

        return ValidationReport(
            appInfo: info,
            codeSignSummary: [verifyResult.combinedOutput, details].filter { !$0.isEmpty }.joined(separator: "\n"),
            gatekeeperSummary: gatekeeperResult.combinedOutput,
            checkedAt: Date()
        )
    }

    static func isDistributionReadySignature(_ codesignDetails: String) -> Bool {
        let acceptedMarkers = [
            "Authority=Developer ID Application:",
            "Authority=Apple Mac OS Application Signing",
            "Authority=Software Signing"
        ]
        return acceptedMarkers.contains { codesignDetails.contains($0) }
    }

    private static func makeSummary(info: AppBundleInfo, details: String, gatekeeperOutput: String) -> String {
        let signingAuthority = firstMatch(in: details, prefix: "Authority=") ?? String(localized: "Unknown signing authority")
        let executable = firstMatch(in: details, prefix: "Executable=") ?? info.displayName
        let gatekeeperStatus = gatekeeperOutput
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? String(localized: "Gatekeeper status unavailable")

        return String(
            localized: """
            App check summary:
            • App: \(info.displayName) \(info.shortVersion)
            • Executable: \(executable)
            • Signing: \(signingAuthority)
            • Gatekeeper: \(gatekeeperStatus)
            """
        ) + "\n"
    }

    private static func firstMatch(in text: String, prefix: String) -> String? {
        text
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .first { $0.hasPrefix(prefix) }
            .map { String($0.dropFirst(prefix.count)) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
}

enum AppValidationError: LocalizedError, Equatable {
    case notDistributionSigned(String)

    var errorDescription: String? {
        switch self {
        case .notDistributionSigned(let authority):
            if authority.isEmpty {
                return "Not signed with a Developer ID Application certificate."
            }
            return "Not signed with Developer ID Application certificate:\n(\(authority))."
        }
    }
}
