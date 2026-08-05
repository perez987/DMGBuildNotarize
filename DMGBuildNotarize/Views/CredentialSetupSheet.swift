import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct CredentialSetupSheet: View {
    @ObservedObject var settings: AppSettings
    let onCompleted: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var profileName: String
    @State private var mode: CredentialSetupMode = .appleID
    @State private var privateKeyPath = ""
    @State private var keyID = ""
    @State private var issuerID = ""
    @State private var appleID = ""
    @State private var teamID = ""
    @State private var appSpecificPassword = ""
    @State private var isRunning = false
    @State private var errorMessage: String?

    init(settings: AppSettings, initialProfileName: String, onCompleted: @escaping (String) -> Void) {
        self.settings = settings
        self.onCompleted = onCompleted
        _profileName = State(initialValue: initialProfileName)
        _mode = State(initialValue: CredentialSetupMode(rawValue: settings.savedNotaryCredentialMode) ?? .appleID)
        _appleID = State(initialValue: settings.savedNotaryAppleID)
        _teamID = State(initialValue: settings.savedNotaryTeamID.isEmpty
            ? (settings.selectedSigningIdentity?.teamID ?? "")
            : settings.savedNotaryTeamID)
        _appSpecificPassword = State(initialValue: settings.savedNotaryAppSpecificPassword)
        _privateKeyPath = State(initialValue: settings.savedNotaryPrivateKeyPath)
        _keyID = State(initialValue: settings.savedNotaryKeyID)
        _issuerID = State(initialValue: settings.savedNotaryIssuerID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Notary Profile")
                    .font(.title3.weight(.semibold))
                Text("Notarization uses App Store Connect credentials. DMGBuildNotarize asks Apple's tool to validate them and save a named profile in Keychain.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Xcode-managed signing certificates do not include a reusable notarization login for third-party apps.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Form {
                Section("Profile") {
                    TextField("Profile Name", text: $profileName)
                }

                Section("Credentials") {
                    Picker("Method", selection: $mode) {
                        ForEach(CredentialSetupMode.allCases) { method in
                            Text(method.title).tag(method)
                        }
                    }
                    .pickerStyle(.segmented)

                    switch mode {
                    case .apiKey:
                        apiKeyFields
                    case .appleID:
                        appleIDFields
                    }
                }
            }
            .formStyle(.grouped)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.body)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            HStack {
                Spacer()

                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .disabled(isRunning)

                Button {
                    Task { await storeProfile() }
                } label: {
                    if isRunning {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Store & Validate", systemImage: "key")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmit || isRunning)
            }
        }
        .padding()
        .frame(width: 560, height: 572)
    }

    private var apiKeyFields: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
            GridRow {
                Text("Private Key")
                    .foregroundStyle(.secondary)

                HStack {
                    Text(privateKeyPath.isEmpty ? "Choose .p8 key" : privateKeyPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)

                    Spacer()

                    Button {
                        choosePrivateKey()
                    } label: {
                        Image(systemName: "folder")
                    }
                    .help("Choose API Private Key")
                }
            }

            GridRow {
                Text("Key ID")
                    .foregroundStyle(.secondary)
                TextField("", text: $keyID)
            }

            GridRow {
                Text("Issuer ID")
                    .foregroundStyle(.secondary)
                TextField("", text: $issuerID)
            }

            GridRow {
                Text("")
                VStack(alignment: .leading, spacing: 8) {
                    Text("Find this on App Store Connect under Users and Access > Integrations > App Store Connect API > Team Keys. It is the Issuer ID for the team, not the Key ID, and individual API keys do not work with notarization.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("If your team cannot create another Team API Key, use the Apple ID method instead with an app-specific password.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        openAPIKeysPage()
                    } label: {
                        Label("Open App Store Connect API Keys", systemImage: "arrow.up.forward.app")
                    }
                    Spacer()
                }
            }
        }
    }

    private var appleIDFields: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
            GridRow {
                Text("Apple ID")
                    .foregroundStyle(.secondary)
                TextField("", text: $appleID)
            }

            GridRow {
                Text("Team ID")
                    .foregroundStyle(.secondary)
                HStack {
                    TextField("", text: $teamID)

                    if let inferredTeamID = settings.selectedSigningIdentity?.teamID {
                        Button("Use \(inferredTeamID)") {
                            teamID = inferredTeamID
                        }
                        .disabled(teamID == inferredTeamID)
                    }
                }
            }

            GridRow {
                Text("App-specific password")
                    .foregroundStyle(.secondary)
                SecureField("", text: appSpecificPasswordBinding)
            }

            GridRow {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Generate this at account.apple.com under Sign-In and Security > App-Specific Passwords. Your Apple Account must have two-factor authentication enabled.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        openAppleAccountPage()
                    } label: {
                        Label("Open Apple Account Passwords", systemImage: "arrow.up.forward.app")
                    }
                }
                .gridCellColumns(2)
            }
        }
    }

    private var canSubmit: Bool {
        guard !profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        switch mode {
        case .apiKey:
            return !privateKeyPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !keyID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !issuerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .appleID:
            return !appleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !teamID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !appSpecificPassword.removingNewlines.isEmpty
        }
    }

    private var appSpecificPasswordBinding: Binding<String> {
        Binding {
            appSpecificPassword
        } set: { newValue in
            appSpecificPassword = newValue.removingNewlines
        }
    }

    private func choosePrivateKey() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        if let privateKeyType = UTType(filenameExtension: "p8") {
            panel.allowedContentTypes = [privateKeyType]
        }

        if panel.runModal() == .OK, let url = panel.url {
            privateKeyPath = url.path
        }
    }

    private func openAPIKeysPage() {
        guard let url = URL(string: "https://appstoreconnect.apple.com/access/integrations/api") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    private func openAppleAccountPage() {
        guard let url = URL(string: "https://account.apple.com/account/manage") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    private func storeProfile() async {
        isRunning = true
        errorMessage = nil

        do {
            let request = NotaryCredentialSetupRequest(
                profileName: profileName,
                authentication: authentication
            )
            let result = try await CredentialSetupService().storeCredentials(request)
            saveCredentialFields()
            settings.notaryProfile = result.profileName
            onCompleted(result.profileName)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }

        isRunning = false
    }

    private func saveCredentialFields() {
        settings.savedNotaryCredentialMode = mode.rawValue
        settings.savedNotaryAppleID = appleID
        settings.savedNotaryTeamID = teamID
        // appSpecificPasswordBinding already strips newlines as the user types;
        // removingNewlines here is a defensive guard before writing to Keychain.
        settings.savedNotaryAppSpecificPassword = appSpecificPassword.removingNewlines
        settings.savedNotaryKeyID = keyID
        settings.savedNotaryIssuerID = issuerID
        settings.savedNotaryPrivateKeyPath = privateKeyPath
    }

    private var authentication: NotaryCredentialAuthentication {
        switch mode {
        case .apiKey:
            return .appStoreConnectAPIKey(
                privateKeyPath: privateKeyPath,
                keyID: keyID,
                issuerID: issuerID
            )
        case .appleID:
            return .appleID(
                appleID: appleID,
                teamID: teamID,
                appSpecificPassword: appSpecificPassword.removingNewlines
            )
        }
    }
}

private enum CredentialSetupMode: String, CaseIterable, Identifiable {
    case appleID
    case apiKey

    var id: String { rawValue }

    var title: String {
        switch self {
        case .apiKey: return String(localized: "Team API Key")
        case .appleID: return String(localized: "Apple ID")
        }
    }
}
