import Foundation
import Combine

@MainActor
final class AppSettings: ObservableObject {
    @Published var signingIdentityHash: String {
        didSet { defaults.set(signingIdentityHash, forKey: Keys.signingIdentityHash) }
    }

    @Published var notaryProfile: String {
        didSet { defaults.set(notaryProfile, forKey: Keys.notaryProfile) }
    }

    @Published var defaultOutputFolderPath: String {
        didSet { defaults.set(defaultOutputFolderPath, forKey: Keys.defaultOutputFolderPath) }
    }

    // Saved notary credential fields (restored when the credential setup sheet opens)
    @Published var savedNotaryCredentialMode: String {
        didSet { defaults.set(savedNotaryCredentialMode, forKey: Keys.savedNotaryCredentialMode) }
    }

    @Published var savedNotaryAppleID: String {
        didSet { defaults.set(savedNotaryAppleID, forKey: Keys.savedNotaryAppleID) }
    }

    @Published var savedNotaryTeamID: String {
        didSet { defaults.set(savedNotaryTeamID, forKey: Keys.savedNotaryTeamID) }
    }

    @Published var savedNotaryKeyID: String {
        didSet { defaults.set(savedNotaryKeyID, forKey: Keys.savedNotaryKeyID) }
    }

    @Published var savedNotaryIssuerID: String {
        didSet { defaults.set(savedNotaryIssuerID, forKey: Keys.savedNotaryIssuerID) }
    }

    @Published var savedNotaryPrivateKeyPath: String {
        didSet { defaults.set(savedNotaryPrivateKeyPath, forKey: Keys.savedNotaryPrivateKeyPath) }
    }

    /// App-specific password stored securely in the Keychain.
    var savedNotaryAppSpecificPassword: String {
        get { KeychainHelper.load(forKey: Keys.savedNotaryAppSpecificPassword) ?? "" }
        set { KeychainHelper.save(newValue, forKey: Keys.savedNotaryAppSpecificPassword) }
    }

    @Published var signingIdentities: [SigningIdentity] = []
    @Published var identityLoadError: String?
    @Published var isLoadingIdentities = false

    private let defaults: UserDefaults
    private let signingClient: SigningClient

    init(defaults: UserDefaults = .standard, signingClient: SigningClient = SigningClient()) {
        self.defaults = defaults
        self.signingClient = signingClient
        self.signingIdentityHash = defaults.string(forKey: Keys.signingIdentityHash) ?? ""
        self.notaryProfile = defaults.string(forKey: Keys.notaryProfile) ?? "DeveloperID"
        self.defaultOutputFolderPath = defaults.string(forKey: Keys.defaultOutputFolderPath)
        ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first?.path
            ?? FileManager.default.homeDirectoryForCurrentUser.path
        self.savedNotaryCredentialMode = defaults.string(forKey: Keys.savedNotaryCredentialMode) ?? ""
        self.savedNotaryAppleID = defaults.string(forKey: Keys.savedNotaryAppleID) ?? ""
        self.savedNotaryTeamID = defaults.string(forKey: Keys.savedNotaryTeamID) ?? ""
        self.savedNotaryKeyID = defaults.string(forKey: Keys.savedNotaryKeyID) ?? ""
        self.savedNotaryIssuerID = defaults.string(forKey: Keys.savedNotaryIssuerID) ?? ""
        self.savedNotaryPrivateKeyPath = defaults.string(forKey: Keys.savedNotaryPrivateKeyPath) ?? ""
    }

    var selectedSigningIdentity: SigningIdentity? {
        signingIdentities.first { $0.hash == signingIdentityHash }
    }

    func refreshSigningIdentities() async {
        isLoadingIdentities = true
        identityLoadError = nil

        do {
            let identities = try await signingClient.loadDeveloperIDApplicationIdentities()
            signingIdentities = identities
            if signingIdentityHash.isEmpty, let first = identities.first {
                signingIdentityHash = first.hash
            }
        } catch {
            identityLoadError = error.localizedDescription
        }

        isLoadingIdentities = false
    }

    private enum Keys {
        static let signingIdentityHash = "signingIdentityHash"
        static let notaryProfile = "notaryProfile"
        static let defaultOutputFolderPath = "defaultOutputFolderPath"
        static let savedNotaryCredentialMode = "savedNotaryCredentialMode"
        static let savedNotaryAppleID = "savedNotaryAppleID"
        static let savedNotaryTeamID = "savedNotaryTeamID"
        static let savedNotaryKeyID = "savedNotaryKeyID"
        static let savedNotaryIssuerID = "savedNotaryIssuerID"
        static let savedNotaryPrivateKeyPath = "savedNotaryPrivateKeyPath"
        static let savedNotaryAppSpecificPassword = "notaryAppSpecificPassword"
    }
}
