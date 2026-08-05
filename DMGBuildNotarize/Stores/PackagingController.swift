import Foundation
import Combine

@MainActor
final class PackagingController: ObservableObject {
    @Published var selectedAppInfo: AppBundleInfo?
    @Published var validationReport: ValidationReport?
    @Published var outputURL: URL?
    @Published var volumeName = ""
    @Published var stageProgress: [StageProgress] = PackagingStage.allCases.map { StageProgress(stage: $0, state: .pending) }
    @Published var logText = ""
    @Published var errorMessage: String?
    @Published var credentialSetupProfileName: String?
    @Published var completedResult: PackagingResult?
    @Published var isRunning = false
    @Published var isInspectingApp = false

    private let settings: AppSettings
    private let validator: AppValidator
    private let pipeline: PackagingPipeline

    init(
        settings: AppSettings,
        validator: AppValidator = AppValidator(),
        pipeline: PackagingPipeline = PackagingPipeline()
    ) {
        self.settings = settings
        self.validator = validator
        self.pipeline = pipeline
    }

    var canBuild: Bool {
        selectedAppInfo != nil &&
        validationReport != nil &&
        outputURL != nil &&
        settings.selectedSigningIdentity != nil &&
        !settings.notaryProfile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !isInspectingApp &&
        !isRunning
    }

    func selectApp(url: URL) async {
        isInspectingApp = true
        errorMessage = nil
        credentialSetupProfileName = nil
        completedResult = nil
        validationReport = nil
        appendLog("Inspecting \(url.path)\n")

        do {
            let info = try AppBundleInfo.load(from: url)
            selectedAppInfo = info
            volumeName = info.defaultVolumeName
            outputURL = defaultOutputURL(for: info)
            appendLog("Loaded \(info.displayName) \(info.shortVersion).\n")

            do {
                let report = try await validator.validate(appURL: url) { [weak self] text in
                    guard let self else { return }
                    Task { @MainActor in self.appendLog(text) }
                }
                validationReport = report
                appendLog("App signature is distribution-ready.\n")
            } catch {
                errorMessage = error.localizedDescription
            }
        } catch {
            clearSelectedApp()
            errorMessage = error.localizedDescription
        }

        isInspectingApp = false
    }

    func chooseOutput(url: URL) {
        outputURL = url
    }

    func build(replaceExisting: Bool = false) async {
        guard let appInfo = selectedAppInfo,
              let outputURL,
              let identity = settings.selectedSigningIdentity
        else {
            errorMessage = "Choose a signed .app, output path, signing identity, and notary profile before building."
            return
        }

        guard validationReport != nil, !isInspectingApp else {
            errorMessage = "Wait for app validation to finish successfully before building."
            return
        }

        let profile = settings.notaryProfile.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !profile.isEmpty else {
            errorMessage = "Enter a notarytool Keychain profile before building."
            return
        }

        let job = PackagingJob(
            appInfo: appInfo,
            outputURL: outputURL,
            volumeName: volumeName.sanitizedVolumeName(defaultValue: appInfo.defaultVolumeName),
            signingIdentity: identity,
            notaryProfile: profile,
            replaceExistingOutput: replaceExisting
        )

        resetProgress()
        isRunning = true
        errorMessage = nil
        credentialSetupProfileName = nil
        completedResult = nil
        appendLog("\nStarting build for \(appInfo.displayName).\n")

        do {
            let result = try await pipeline.run(
                job: job,
                onStage: { [weak self] stage in
                    guard let self else { return }
                    Task { @MainActor in self.markStageRunning(stage) }
                },
                print: { [weak self] text in
                    guard let self else { return }
                    Task { @MainActor in self.appendLog(text) }
                }
            )

            markAllSucceeded()
            completedResult = result
            appendLog("Finished \(result.outputURL.path).\n")
        } catch {
            markCurrentStageFailed(error.localizedDescription)
            errorMessage = error.localizedDescription
            if case .some(.missingKeychainProfile(let profile)) = error as? NotaryError {
                credentialSetupProfileName = profile
            }
        }

        isRunning = false
    }

    func resetProgress() {
        stageProgress = PackagingStage.allCases.map { StageProgress(stage: $0, state: .pending) }
        logText = ""
    }

    func recordCredentialSetupCompleted(profileName: String) {
        errorMessage = nil
        credentialSetupProfileName = nil
        appendLog("Stored notarytool Keychain profile \(profileName).\n")
    }

    private func clearSelectedApp() {
        selectedAppInfo = nil
        outputURL = nil
        volumeName = ""
    }

    private func defaultOutputURL(for info: AppBundleInfo) -> URL {
        let folder = URL(fileURLWithPath: settings.defaultOutputFolderPath, isDirectory: true)
        return folder.appendingPathComponent(info.defaultOutputFileName)
    }

    private func appendLog(_ text: String) {
        logText.append(text)
    }

    private func markStageRunning(_ stage: PackagingStage) {
        for index in stageProgress.indices {
            if stageProgress[index].stage == stage {
                stageProgress[index].state = .running
            } else if stageProgress[index].state == .running {
                stageProgress[index].state = .succeeded
            }
        }
    }

    private func markCurrentStageFailed(_ message: String) {
        if let runningIndex = stageProgress.firstIndex(where: { $0.state == .running }) {
            stageProgress[runningIndex].state = .failed(message)
        } else if let firstPending = stageProgress.firstIndex(where: { $0.state == .pending }) {
            stageProgress[firstPending].state = .failed(message)
        }
    }

    private func markAllSucceeded() {
        for index in stageProgress.indices {
            stageProgress[index].state = .succeeded
        }
    }
}
