import Foundation

struct NotaryClient: Sendable {
    let runner: any ProcessRunning

    nonisolated init(runner: any ProcessRunning = ProcessRunner()) {
        self.runner = runner
    }

    func validateKeychainProfile(_ keychainProfile: String, onOutput: @escaping @Sendable (String) -> Void = { _ in }) async throws {
        do {
            try await runner.run(
                .system(
                    "/usr/bin/xcrun",
                    [
                        "notarytool",
                        "history",
                        "--keychain-profile",
                        keychainProfile,
                        "--output-format",
                        "json"
                    ],
                    timeout: 60
                ),
                onOutput: onOutput
            )
        } catch {
            throw Self.validationError(from: error, keychainProfile: keychainProfile)
        }
    }

    func submitAndWait(dmgURL: URL, keychainProfile: String, onOutput: @escaping @Sendable (String) -> Void = { _ in }) async throws -> NotarySubmission {
        let result: ProcessResult
        do {
            result = try await runner.run(
                .system(
                    "/usr/bin/xcrun",
                    [
                        "notarytool",
                        "submit",
                        dmgURL.path,
                        "--keychain-profile",
                        keychainProfile,
                        "--wait",
                        "--output-format",
                        "json"
                    ],
                    timeout: 60 * 60
                ),
                onOutput: onOutput
            )
        } catch {
            throw Self.normalizedError(from: error, keychainProfile: keychainProfile)
        }

        let submission = try Self.parseSubmission(result.standardOutput.isEmpty ? result.combinedOutput : result.standardOutput)
        guard submission.status.lowercased() == "accepted" else {
            throw NotaryError.rejected(submission)
        }
        return submission
    }

    func staple(dmgURL: URL, onOutput: @escaping @Sendable (String) -> Void = { _ in }) async throws {
        try await runner.run(.system("/usr/bin/xcrun", ["stapler", "staple", dmgURL.path]), onOutput: onOutput)
    }

    func validateStaple(dmgURL: URL, onOutput: @escaping @Sendable (String) -> Void = { _ in }) async throws {
        try await runner.run(.system("/usr/bin/xcrun", ["stapler", "validate", dmgURL.path]), onOutput: onOutput)
    }

    static func parseSubmission(_ jsonText: String) throws -> NotarySubmission {
        let data = Data(jsonText.utf8)
        return try JSONDecoder().decode(NotarySubmission.self, from: data)
    }

    static func validationError(from error: Error, keychainProfile: String) -> Error {
        let normalized = normalizedError(from: error, keychainProfile: keychainProfile)
        if normalized is NotaryError {
            return normalized
        }

        return NotaryError.profileValidationFailed(
            profile: keychainProfile,
            details: normalized.localizedDescription
        )
    }

    static func normalizedError(from error: Error, keychainProfile: String) -> Error {
        if let notaryError = error as? NotaryError {
            return notaryError
        }

        guard let runnerError = error as? ProcessRunnerError else {
            return error
        }

        if case .nonZeroExit(let result) = runnerError,
           result.combinedOutput.range(of: "No Keychain password item found for profile", options: .caseInsensitive) != nil {
            return NotaryError.missingKeychainProfile(keychainProfile)
        }

        return runnerError
    }
}

struct NotarySubmission: Decodable, Equatable, Sendable {
    let id: String
    let status: String
    let message: String?

    nonisolated static func == (lhs: NotarySubmission, rhs: NotarySubmission) -> Bool {
        lhs.id == rhs.id && lhs.status == rhs.status && lhs.message == rhs.message
    }
}

enum NotaryError: LocalizedError, Equatable {
    case missingKeychainProfile(String)
    case profileValidationFailed(profile: String, details: String)
    case rejected(NotarySubmission)

    var errorDescription: String? {
        switch self {
        case .missingKeychainProfile(let profile):
            return """
            No notarytool Keychain profile named "\(profile)" was found.

            Create or validate the profile, then run Build DMG again:
            xcrun notarytool store-credentials \(profile.shellSingleQuoted) --validate
            """
        case .profileValidationFailed(let profile, let details):
            return """
            Could not validate notarytool Keychain profile "\(profile)".

            \(details)
            """
        case .rejected(let submission):
            let message = submission.message.map { "\n\($0)" } ?? ""
            return "Notarization finished with status \(submission.status) for submission \(submission.id).\(message)"
        }
    }
}
