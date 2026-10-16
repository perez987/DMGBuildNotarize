import Foundation

struct CredentialSetupService {
    let runner: any ProcessRunning

    nonisolated init(runner: any ProcessRunning = ProcessRunner()) {
        self.runner = runner
    }

    func storeCredentials(_ request: NotaryCredentialSetupRequest) async throws -> CredentialSetupResult {
        let profile = try request.validatedProfileName()
        let arguments = try Self.storeCredentialsArguments(for: request)

        do {
            try await runner.run(.system("/usr/bin/xcrun", arguments, timeout: 300), onOutput: { _ in })
            return CredentialSetupResult(profileName: profile)
        } catch {
            throw Self.credentialSetupError(from: error)
        }
    }

    static func storeCredentialsArguments(for request: NotaryCredentialSetupRequest) throws -> [String] {
        let profile = try request.validatedProfileName()
        var arguments = ["notarytool", "store-credentials", profile, "--validate"]

        switch request.authentication {
        case .appStoreConnectAPIKey(let privateKeyPath, let keyID, let issuerID):
            let keyPath = privateKeyPath.trimmingCharacters(in: .whitespacesAndNewlines)
            let keyID = keyID.trimmingCharacters(in: .whitespacesAndNewlines)
            let issuerID = issuerID.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !keyPath.isEmpty else { throw CredentialSetupError.missingAPIPrivateKey }
            guard !keyID.isEmpty else { throw CredentialSetupError.missingAPIKeyID }
            guard !issuerID.isEmpty else { throw CredentialSetupError.missingAPIIssuerID }

            arguments.append(contentsOf: ["--key", keyPath, "--key-id", keyID, "--issuer", issuerID])
        case .appleID(let appleID, let teamID, let appSpecificPassword):
            let appleID = appleID.trimmingCharacters(in: .whitespacesAndNewlines)
            let teamID = teamID.trimmingCharacters(in: .whitespacesAndNewlines)
            let appSpecificPassword = appSpecificPassword.removingNewlines
            guard !appleID.isEmpty else { throw CredentialSetupError.missingAppleID }
            guard !teamID.isEmpty else { throw CredentialSetupError.missingTeamID }
            guard !appSpecificPassword.isEmpty else { throw CredentialSetupError.missingAppSpecificPassword }

            arguments.append(contentsOf: [
                "--apple-id",
                appleID,
                "--team-id",
                teamID,
                "--password",
                appSpecificPassword
            ])
        }

        return arguments
    }

    private static func credentialSetupError(from error: Error) -> Error {
        guard let runnerError = error as? ProcessRunnerError else {
            return CredentialSetupError.notarytoolFailed(error.localizedDescription)
        }

        switch runnerError {
        case .nonZeroExit(let result):
            return CredentialSetupError.notarytoolFailed(result.combinedOutput)
        case .timedOut:
            return CredentialSetupError.notarytoolFailed("notarytool credential setup timed out.")
        }
    }
}

struct NotaryCredentialSetupRequest: Equatable, Sendable {
    let profileName: String
    let authentication: NotaryCredentialAuthentication

    func validatedProfileName() throws -> String {
        let profile = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !profile.isEmpty else {
            throw CredentialSetupError.missingProfileName
        }
        return profile
    }
}

enum NotaryCredentialAuthentication: Equatable, Sendable {
    case appStoreConnectAPIKey(privateKeyPath: String, keyID: String, issuerID: String)
    case appleID(appleID: String, teamID: String, appSpecificPassword: String)
}

struct CredentialSetupResult: Equatable, Sendable {
    let profileName: String
}

enum CredentialSetupError: LocalizedError {
    case missingProfileName
    case missingAPIPrivateKey
    case missingAPIKeyID
    case missingAPIIssuerID
    case missingAppleID
    case missingTeamID
    case missingAppSpecificPassword
    case notarytoolFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingProfileName:
            return "Enter a notarytool Keychain profile name before starting setup."
        case .missingAPIPrivateKey:
            return "Choose an App Store Connect API private key."
        case .missingAPIKeyID:
            return "Enter the App Store Connect API key ID."
        case .missingAPIIssuerID:
            return "Enter the App Store Connect API issuer ID."
        case .missingAppleID:
            return "Enter the Apple ID for notarization."
        case .missingTeamID:
            return "Enter the Apple Developer Team ID."
        case .missingAppSpecificPassword:
            return "Enter an app-specific password."
        case .notarytoolFailed(let details):
            let trimmed = details.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return "notarytool could not store or validate the credential profile."
            }
            return trimmed
        }
    }
}
