import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var isShowingCredentialSetup = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("Signing") {
                Picker("Identity", selection: $settings.signingIdentityHash) {
                    if settings.signingIdentities.isEmpty {
                        Text("No Developer ID Application identities").tag("")
                    }

                    ForEach(settings.signingIdentities) { identity in
                        Text(identity.displayName).tag(identity.hash)
                    }
                }
                .frame(maxWidth: .infinity)

                HStack {
                    Button {
                        Task { await settings.refreshSigningIdentities() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }

                    if settings.isLoadingIdentities {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if let identityLoadError = settings.identityLoadError {
                    Text(identityLoadError)
                        .font(.body)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }

            Section("Notarization") {
                TextField("Keychain Profile", text: $settings.notaryProfile)

                HStack {
                    Button {
                        isShowingCredentialSetup = true
                    } label: {
                        Label("Create or Validate Profile", systemImage: "key")
                    }

                    Spacer()
                }
            }

            Section("Output") {
                HStack {
                    Text(settings.defaultOutputFolderPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)

                    Spacer()

                    Button {
                        chooseDefaultOutputFolder()
                    } label: {
                        Image(systemName: "folder")
                    }
                    .help("Choose Default Output Folder")
                    Button("Cancel", role: .cancel) {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onExitCommand { dismiss() }
        .task {
            await settings.refreshSigningIdentities()
        }
        .sheet(isPresented: $isShowingCredentialSetup) {
            CredentialSetupSheet(settings: settings, initialProfileName: settings.notaryProfile) { profile in
                settings.notaryProfile = profile
            }
        }
    }

    private func chooseDefaultOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: settings.defaultOutputFolderPath, isDirectory: true)

        if panel.runModal() == .OK, let url = panel.url {
            settings.defaultOutputFolderPath = url.path
        }
    }
}
