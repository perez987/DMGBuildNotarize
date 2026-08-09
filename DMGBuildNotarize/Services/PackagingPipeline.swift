import Foundation

struct PackagingPipeline: @unchecked Sendable {
    let validator: AppValidator
    let dmgBuilder: DmgBuilder
    let signingClient: SigningClient
    let notaryClient: NotaryClient
    /// Non-nil when `create-dmg` is installed; nil falls back to AppleScript.
    let createDmgRunner: CreateDmgRunner?

    /// The ordered list of stages this pipeline will execute.
    ///
    /// When `create-dmg` is available the four AppleScript-based DMG-building
    /// stages are replaced with a single `buildDMG` stage. Otherwise the full
    /// ten-stage AppleScript flow is used.
    var stages: [PackagingStage] {
        if createDmgRunner != nil {
            return [
                .validateApp, .validateNotaryProfile,
                .buildDMG,
                .signDMG, .notarize, .staple, .verify
            ]
        } else {
            return [
                .validateApp, .validateNotaryProfile,
                .stageVolume, .createReadWriteImage, .applyFinderLayout, .convertCompressedImage,
                .signDMG, .notarize, .staple, .verify
            ]
        }
    }

    nonisolated init(
        runner: any ProcessRunning = ProcessRunner(),
        fileManager: FileManager = .default
    ) {
        self.validator = AppValidator(runner: runner)
        self.dmgBuilder = DmgBuilder(runner: runner, fileManager: fileManager)
        self.signingClient = SigningClient(runner: runner)
        self.notaryClient = NotaryClient(runner: runner)
        self.createDmgRunner = CreateDmgRunner.findCreateDmg() != nil
            ? CreateDmgRunner(runner: runner)
            : nil
    }

    func run(
        job: PackagingJob,
        onStage: @escaping @Sendable (PackagingStage) -> Void,
        print: @escaping @Sendable (String) -> Void
    ) async throws -> PackagingResult {
        if let createDmgRunner {
            return try await runWithCreateDmg(
                runner: createDmgRunner,
                job: job,
                onStage: onStage,
                print: print
            )
        } else {
            return try await runWithAppleScript(job: job, onStage: onStage, print: print)
        }
    }

    // MARK: - create-dmg path

    private func runWithCreateDmg(
        runner: CreateDmgRunner,
        job: PackagingJob,
        onStage: @escaping @Sendable (PackagingStage) -> Void,
        print: @escaping @Sendable (String) -> Void
    ) async throws -> PackagingResult {
        let context = try dmgBuilder.createContext(for: job)
        var submissionID: String?

        do {
            onStage(.validateApp)
            print("Validating app bundle: \(job.appInfo.url.lastPathComponent)\n")
            _ = try await validator.validate(appURL: job.appInfo.url)
            print("App bundle is distribution-signed (\(job.appInfo.displayName) \(job.appInfo.shortVersion)).\n")

            onStage(.validateNotaryProfile)
            print("Validating notary Keychain profile \"\(job.notaryProfile)\"…\n")
            try await notaryClient.validateKeychainProfile(job.notaryProfile)
            print("Notary profile is valid.\n")

            onStage(.buildDMG)
            print("Building polished DMG with create-dmg…\n")
            try dmgBuilder.prepareOutput(job.outputURL, replaceExisting: job.replaceExistingOutput)
            try dmgBuilder.fileManager.createDirectory(at: context.workDirectory, withIntermediateDirectories: true)
            try await runner.run(
                appURL: job.appInfo.url,
                outputFolder: context.workDirectory,
                onOutput: print
            )
            guard let resultDMG = CreateDmgRunner.findResultingDMG(in: context.workDirectory) else {
                throw CreateDmgError.dmgNotFound
            }
            try dmgBuilder.fileManager.moveItem(at: resultDMG, to: context.compressedImageURL)
            print("DMG built.\n")

            onStage(.signDMG)
            print("Signing DMG with identity \"\(job.signingIdentity.name)\"…\n")
            try await signingClient.signDMG(context.compressedImageURL, identity: job.signingIdentity)
            print("DMG signed.\n")

            onStage(.notarize)
            print("Submitting DMG to Apple notary service (this may take several minutes)…\n")
            let submission = try await notaryClient.submitAndWait(dmgURL: context.compressedImageURL, keychainProfile: job.notaryProfile)
            submissionID = submission.id
            print("Notarization accepted (submission ID: \(submission.id)).\n")

            onStage(.staple)
            print("Stapling notarization ticket to DMG…\n")
            try await notaryClient.staple(dmgURL: context.compressedImageURL)
            print("Ticket stapled.\n")

            onStage(.verify)
            print("Verifying stapled DMG…\n")
            try await notaryClient.validateStaple(dmgURL: context.compressedImageURL)
            try await dmgBuilder.verifyImage(context.compressedImageURL)
            print("Verification passed.\n")

            try dmgBuilder.publishOutput(context: context, replaceExisting: job.replaceExistingOutput)
            print("DMG written to: \(job.outputURL.path)\n")

            try? dmgBuilder.clean(context: context)
            return PackagingResult(outputURL: job.outputURL, notarizationID: submissionID)
        } catch {
            try? dmgBuilder.clean(context: context)
            throw error
        }
    }

    // MARK: - AppleScript path (fallback when create-dmg is not installed)

    private func runWithAppleScript(
        job: PackagingJob,
        onStage: @escaping @Sendable (PackagingStage) -> Void,
        print: @escaping @Sendable (String) -> Void
    ) async throws -> PackagingResult {
        let context = try dmgBuilder.createContext(for: job)
        var submissionID: String?

        do {
            onStage(.validateApp)
            print("Validating app bundle: \(job.appInfo.url.lastPathComponent)\n")
            _ = try await validator.validate(appURL: job.appInfo.url)
            print("App bundle is distribution-signed (\(job.appInfo.displayName) \(job.appInfo.shortVersion)).\n")

            onStage(.validateNotaryProfile)
            print("Validating notary Keychain profile \"\(job.notaryProfile)\"…\n")
            try await notaryClient.validateKeychainProfile(job.notaryProfile)
            print("Notary profile is valid.\n")

            onStage(.stageVolume)
            print("Staging installer volume for \"\(job.volumeName)\"…\n")
            try dmgBuilder.prepareOutput(job.outputURL, replaceExisting: job.replaceExistingOutput)
            try dmgBuilder.stageVolume(job: job, context: context)
            print("Installer volume staged.\n")

            onStage(.createReadWriteImage)
            print("Creating writable DMG image…\n")
            try await dmgBuilder.createReadWriteImage(job: job, context: context)
            print("Writable DMG created.\n")

            onStage(.applyFinderLayout)
            print("Applying Finder window layout…\n")
            try await dmgBuilder.applyFinderLayout(job: job, context: context)
            print("Finder layout applied.\n")

            onStage(.convertCompressedImage)
            print("Compressing DMG image…\n")
            try await dmgBuilder.convertCompressedImage(context: context)
            print("DMG compressed.\n")

            onStage(.signDMG)
            print("Signing DMG with identity \"\(job.signingIdentity.name)\"…\n")
            try await signingClient.signDMG(context.compressedImageURL, identity: job.signingIdentity)
            print("DMG signed.\n")

            onStage(.notarize)
            print("Submitting DMG to Apple notary service (this may take several minutes)…\n")
            let submission = try await notaryClient.submitAndWait(dmgURL: context.compressedImageURL, keychainProfile: job.notaryProfile)
            submissionID = submission.id
            print("Notarization accepted (submission ID: \(submission.id)).\n")

            onStage(.staple)
            print("Stapling notarization ticket to DMG…\n")
            try await notaryClient.staple(dmgURL: context.compressedImageURL)
            print("Ticket stapled.\n")

            onStage(.verify)
            print("Verifying stapled DMG…\n")
            try await notaryClient.validateStaple(dmgURL: context.compressedImageURL)
            try await dmgBuilder.verifyImage(context.compressedImageURL)
            print("Verification passed.\n")

            try dmgBuilder.publishOutput(context: context, replaceExisting: job.replaceExistingOutput)
            print("DMG written to: \(job.outputURL.path)\n")

            try? dmgBuilder.clean(context: context)
            return PackagingResult(outputURL: job.outputURL, notarizationID: submissionID)
        } catch {
            try? dmgBuilder.clean(context: context)
            throw error
        }
    }
}

