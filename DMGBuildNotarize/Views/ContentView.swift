import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var settings: AppSettings
    @StateObject private var controller: PackagingController
    @State private var showReplaceConfirmation = false
    @State private var showCredentialSetup = false

    init(settings: AppSettings) {
        self.settings = settings
        _controller = StateObject(wrappedValue: PackagingController(settings: settings))
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                DropTargetView(isInspecting: controller.isInspectingApp) { url in
                    Task { await controller.selectApp(url: url) }
                }
                .padding()

                Divider()

                StageListView(stages: controller.stageProgress)
            }
            .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 360)
        } detail: {
            VStack(spacing: 0) {
                HeaderView(controller: controller, settings: settings)
                    .padding()

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        AppSummaryView(info: controller.selectedAppInfo, report: controller.validationReport)
                        OutputSettingsView(controller: controller)
                        ProgressLogView(
                            logText: controller.logText,
                            errorMessage: controller.errorMessage,
                            credentialSetupProfileName: controller.credentialSetupProfileName,
                            result: controller.completedResult
                        ) {
                            showCredentialSetup = true
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .toolbar {
                ToolbarItemGroup {
                    Button {
                        chooseApp()
                    } label: {
                        Label("Choose App", systemImage: "app.badge")
                    }
                    .help("Choose App")

                    Button {
                        startBuild()
                    } label: {
                        Label("Build DMG", systemImage: "shippingbox")
                    }
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(!controller.canBuild)
                    .help("Build DMG")
                }
            }
        }
        .task {
            await settings.refreshSigningIdentities()
        }
        .alert("Replace existing DMG?", isPresented: $showReplaceConfirmation) {
            Button("Replace", role: .destructive) {
                Task { await controller.build(replaceExisting: true) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(controller.outputURL?.path ?? "")
        }
        .sheet(isPresented: $showCredentialSetup) {
            CredentialSetupSheet(
                settings: settings,
                initialProfileName: controller.credentialSetupProfileName ?? settings.notaryProfile
            ) { profile in
                settings.notaryProfile = profile
                controller.recordCredentialSetupCompleted(profileName: profile)
            }
        }
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if panel.runModal() == .OK, let url = panel.url {
            Task { await controller.selectApp(url: url) }
        }
    }

    private func startBuild() {
        if let outputURL = controller.outputURL, FileManager.default.fileExists(atPath: outputURL.path) {
            showReplaceConfirmation = true
        } else {
            Task { await controller.build() }
        }
    }
}

private struct HeaderView: View {
    let controller: PackagingController
    let settings: AppSettings

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "opticaldiscdrive")
                .font(.system(size: 32))
                .foregroundStyle(Color.accentColor)
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(controller.selectedAppInfo?.displayName ?? "DMGBuildNotarize")
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)

                Text(statusText)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if controller.isRunning {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private var statusText: String {
        if controller.isRunning {
            return String(localized: "Packaging and notarizing")
        }
        if let result = controller.completedResult {
            return String(format: String(localized: "Ready: %@"), result.outputURL.lastPathComponent)
        }
        if settings.selectedSigningIdentity == nil {
            return String(localized: "Choose a Developer ID Application identity in Settings")
        }
        if controller.selectedAppInfo != nil, controller.validationReport != nil {
            return String(localized: "App signature verified")
        }
        return String(localized: "Drop a signed .app to begin")
    }
}
