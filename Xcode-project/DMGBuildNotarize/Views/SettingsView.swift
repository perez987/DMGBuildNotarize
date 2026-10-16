import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var isShowingCredentialSetup = false
    @State private var selectedLanguageCode: String
    @State private var pendingLanguage: AppLanguage?
    @State private var showLanguageChangeAlert = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    init(settings: AppSettings) {
        self.settings = settings
        _selectedLanguageCode = State(initialValue: settings.selectedAppLanguageCode)
    }

    var body: some View {
        ZStack {
            AppTheme.windowGradient(for: colorScheme)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerCard
                    signingCard
                    notarizationCard
                    outputCard
                    languageCard
                    footerCard
                }
                .padding(20)
            }
        }
        .onExitCommand { dismiss() }
        .task {
            await settings.refreshSigningIdentities()
        }
        .sheet(isPresented: $isShowingCredentialSetup) {
            CredentialSetupSheet(settings: settings, initialProfileName: settings.notaryProfile) { profile in
                settings.notaryProfile = profile
            }
        }
        .alert(String(localized: "Restart required"), isPresented: $showLanguageChangeAlert, presenting: pendingLanguage) { language in
            Button(String(localized: "Cancel"), role: .cancel) {
                pendingLanguage = nil
            }
            Button(String(localized: "Change Language")) {
                settings.setSelectedAppLanguageCode(language.code)
                selectedLanguageCode = language.code
                pendingLanguage = nil
            }
        } message: { language in
            Text(
                String(
                    format: String(localized: "DMGBuildNotarize needs to restart before %@ is applied. Do you want to continue?"),
                    language.nativeName
                )
            )
        }
    }

    private var selectedLanguage: AppLanguage {
        AppLanguage.resolve(code: selectedLanguageCode)
    }

    private var headerCard: some View {
        PreferenceCard(accentOpacity: 0.24) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(AppTheme.accentGradient)
                    .frame(width: 48, height: 48)
                    .background {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(AppTheme.accentGradient)
                            .opacity(colorScheme == .dark ? 0.18 : 0.22)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Settings"))
                        .font(.title2.weight(.semibold))
                    Text(String(localized: "Manage signing, notarization, language, and output preferences."))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
        }
    }

    private var signingCard: some View {
        PreferenceCard {
            PreferenceSectionHeader(
                "Signing",
                systemImage: "checkmark.shield",
                subtitle: String(localized: "Choose the Developer ID Application identity used for the finished DMG.")
            )

            PreferenceField("Identity") {
                Picker("", selection: $settings.signingIdentityHash) {
                    if settings.signingIdentities.isEmpty {
                        Text("No Developer ID Application identities").tag("")
                    }

                    ForEach(settings.signingIdentities) { identity in
                        Text(identity.displayName).tag(identity.hash)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 10) {
                Button {
                    Task { await settings.refreshSigningIdentities() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)

                if settings.isLoadingIdentities {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let identityLoadError = settings.identityLoadError {
                Label(identityLoadError, systemImage: "exclamationmark.triangle.fill")
                    .font(.body)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
    }

    private var notarizationCard: some View {
        PreferenceCard {
            PreferenceSectionHeader(
                "Notarization",
                systemImage: "key.horizontal.fill",
                subtitle: String(localized: "Save or validate the keychain profile used for notarization submissions.")
            )

            PreferenceField("Keychain Profile") {
                TextField("Keychain Profile", text: $settings.notaryProfile)
                    .textFieldStyle(.roundedBorder)
            }

            Button {
                isShowingCredentialSetup = true
            } label: {
                Label("Create or Validate Profile", systemImage: "key")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private var outputCard: some View {
        PreferenceCard {
            PreferenceSectionHeader(
                "Output Folder",
                systemImage: "folder.fill",
                subtitle: String(localized: "Choose where new DMGs are created by default.")
            )

            PreferenceField("Output") {
                HStack(spacing: 12) {
                    Text(settings.defaultOutputFolderPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)

                    Spacer(minLength: 12)

                    Button {
                        chooseDefaultOutputFolder()
                    } label: {
                        Label("Choose Folder", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var languageCard: some View {
        PreferenceCard {
            PreferenceSectionHeader(
                "Language",
                systemImage: "globe",
                subtitle: String(localized: "Select the display language used after the next app restart.")
            )

            VStack(spacing: 12) {
                ForEach(AppLanguage.supported) { language in
                    Button {
                        guard language.code != selectedLanguageCode else { return }
                        pendingLanguage = language
                        showLanguageChangeAlert = true
                    } label: {
                        LanguageOptionRow(language: language, isSelected: selectedLanguageCode == language.code)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                Text(String(localized: "Selected language"))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(selectedLanguage.nativeName)
                    .font(.subheadline.weight(.semibold))
            }
        }
    }

    private var footerCard: some View {
        PreferenceCard(accentOpacity: 0.12) {
            HStack {
                Spacer()

                Button(String(localized: "Close")) {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.cancelAction)
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

private struct LanguageOptionRow: View {
    let language: AppLanguage
    let isSelected: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 14) {
            Text(language.flag)
                .font(.system(size: 28))

            VStack(alignment: .leading, spacing: 2) {
                Text(language.nativeName)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(language.code.uppercased())
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(isSelected ? AnyShapeStyle(AppTheme.accentGradient) : AnyShapeStyle(.secondary))
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AppTheme.raisedSurfaceFill(for: colorScheme, emphasized: isSelected))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(AppTheme.accentGlow(for: colorScheme))
                        .opacity(isSelected ? (colorScheme == .dark ? 0.28 : 0.58) : (colorScheme == .dark ? 0.08 : 0.12))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(
                            isSelected ? AppTheme.accentGradient : AppTheme.borderGradient(for: colorScheme),
                            lineWidth: isSelected ? 1.6 : 1
                        )
                }
        }
    }
}
