import XCTest
@testable import DMGBuildNotarize

final class DMGBuildNotarizeTests: XCTestCase {
    func testAppDeclaresAppleEventsUsageDescription() {
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "NSAppleEventsUsageDescription") as? String,
            "DMGBuildNotarize uses Finder automation to create custom installer window layouts."
        )
    }

    func testAppleScriptRunnerPropagatesExecutionErrors() async {
        do {
            try await DefaultAppleScriptRunner().execute(#"error "Deliberate test failure" number -2700"#)
            XCTFail("Expected the AppleScript execution error to be thrown")
        } catch {
            let error = error as NSError
            XCTAssertEqual(error.domain, "NSAppleScript")
            XCTAssertEqual(error.code, -2700)
            XCTAssertEqual(error.localizedDescription, "Deliberate test failure")
        }
    }

    func testAppBundleInfoLoadsRequiredMetadata() throws {
        let appURL = try makeFixtureApp(displayName: "Fixture App", version: "1.2.3")

        let info = try AppBundleInfo.load(from: appURL)

        XCTAssertEqual(info.displayName, "Fixture App")
        XCTAssertEqual(info.bundleIdentifier, "com.example.fixture")
        XCTAssertEqual(info.shortVersion, "1.2.3")
        XCTAssertEqual(info.defaultOutputFileName, "Fixture App-1.2.3.dmg")
    }

    func testFileAndVolumeNamesAreSanitized() {
        XCTAssertEqual("Bad/Name:1".sanitizedFileComponent, "Bad-Name-1")
        XCTAssertEqual("Bad/Name:1".sanitizedVolumeName(defaultValue: "Installer"), "Bad Name 1")
        XCTAssertEqual("///".sanitizedVolumeName(defaultValue: "Installer"), "Installer")
    }

    func testSigningIdentityParserFiltersDeveloperIDApplicationIdentities() {
        let output = """
          1) ABCDEF1234567890 "Developer ID Application: Example Co (TEAMID)"
          2) 1111111111111111 "Apple Development: Example Co (TEAMID)"
             2 valid identities found
        """

        let identities = SigningClient.parseDeveloperIDApplicationIdentities(output)

        XCTAssertEqual(identities, [SigningIdentity(hash: "ABCDEF1234567890", name: "Developer ID Application: Example Co (TEAMID)")])
    }

    func testSigningIdentityExtractsTeamID() {
        XCTAssertEqual(
            SigningIdentity.extractTeamID(from: "Developer ID Application: Example Co (TEAMID1234)"),
            "TEAMID1234"
        )
        XCTAssertNil(SigningIdentity.extractTeamID(from: "Developer ID Application: Example Co"))
    }

    func testDistributionReadySignatureDetection() {
        XCTAssertTrue(AppValidator.isDistributionReadySignature("Authority=Developer ID Application: Example Co (TEAMID)"))
        XCTAssertFalse(AppValidator.isDistributionReadySignature("Authority=Apple Development: Example Co (TEAMID)"))
    }

    func testAppValidationLogsConciseSummaryInsteadOfToolOutput() async throws {
        let appURL = try makeFixtureApp(displayName: "Fixture App", version: "1.2.3")
        let runner = MockProcessRunner(results: [
            ProcessResult(
                command: .system("/usr/bin/codesign", ["--verify"]),
                terminationStatus: 0,
                standardOutput: "codesign verbose output",
                standardError: ""
            ),
            ProcessResult(
                command: .system("/usr/bin/codesign", ["-dv"]),
                terminationStatus: 0,
                standardOutput: "",
                standardError: """
                Executable=/Applications/Fixture App.app/Contents/MacOS/Fixture App
                Authority=Developer ID Application: Example Co (TEAMID)
                """
            ),
            ProcessResult(
                command: .system("/usr/sbin/spctl", ["-a"]),
                terminationStatus: 0,
                standardOutput: "",
                standardError: """
                /Applications/Fixture App.app: accepted
                source=Notarized Developer ID
                """
            )
        ])
        let validator = AppValidator(runner: runner)
        var logged = ""

        _ = try await validator.validate(appURL: appURL) { text in
            logged.append(text)
        }

        XCTAssertTrue(logged.contains("Checking code signature…"))
        XCTAssertTrue(logged.contains("Reading signing certificate details…"))
        XCTAssertTrue(logged.contains("Checking Gatekeeper acceptance…"))
        XCTAssertTrue(logged.contains("App check summary:"))
        XCTAssertTrue(logged.contains("Signing: Developer ID Application: Example Co (TEAMID)"))
        XCTAssertTrue(logged.contains("Gatekeeper: /Applications/Fixture App.app: accepted"))
        XCTAssertFalse(logged.contains("codesign verbose output"))
        XCTAssertFalse(logged.contains("source=Notarized Developer ID"))
    }

    func testNotarySubmissionParsing() throws {
        let submission = try NotaryClient.parseSubmission("""
        {"id":"1234","status":"Accepted","message":null}
        """)

        XCTAssertEqual(submission, NotarySubmission(id: "1234", status: "Accepted", message: nil))
    }

    func testMissingNotaryProfileErrorIsActionable() {
        let result = ProcessResult(
            command: .system("/usr/bin/xcrun", ["notarytool", "submit"]),
            terminationStatus: 69,
            standardOutput: "",
            standardError: """
            Error: No Keychain password item found for profile: DeveloperID

            Run 'notarytool store-credentials' to create another credential profile.
            """
        )

        let error = NotaryClient.normalizedError(
            from: ProcessRunnerError.nonZeroExit(result),
            keychainProfile: "DeveloperID"
        )

        XCTAssertEqual(error as? NotaryError, .missingKeychainProfile("DeveloperID"))
        XCTAssertTrue(error.localizedDescription.contains("Create or validate the profile"))
        XCTAssertTrue(error.localizedDescription.contains("xcrun notarytool store-credentials 'DeveloperID' --validate"))
    }

    func testCredentialSetupBuildsAPIKeyArguments() throws {
        let request = NotaryCredentialSetupRequest(
            profileName: "DeveloperID",
            authentication: .appStoreConnectAPIKey(
                privateKeyPath: "/Users/james/AuthKey_ABC123.p8",
                keyID: "ABC123",
                issuerID: "11111111-2222-3333-4444-555555555555"
            )
        )

        XCTAssertEqual(
            try CredentialSetupService.storeCredentialsArguments(for: request),
            [
                "notarytool",
                "store-credentials",
                "DeveloperID",
                "--validate",
                "--key",
                "/Users/james/AuthKey_ABC123.p8",
                "--key-id",
                "ABC123",
                "--issuer",
                "11111111-2222-3333-4444-555555555555"
            ]
        )
    }

    func testCredentialSetupBuildsAppleIDArguments() throws {
        let request = NotaryCredentialSetupRequest(
            profileName: "DeveloperID",
            authentication: .appleID(
                appleID: "developer@example.com",
                teamID: "TEAMID1234",
                appSpecificPassword: "app-specific-password"
            )
        )

        XCTAssertEqual(
            try CredentialSetupService.storeCredentialsArguments(for: request),
            [
                "notarytool",
                "store-credentials",
                "DeveloperID",
                "--validate",
                "--apple-id",
                "developer@example.com",
                "--team-id",
                "TEAMID1234",
                "--password",
                "app-specific-password"
            ]
        )
    }

    func testCredentialSetupRemovesNewlinesFromAppSpecificPassword() throws {
        let request = NotaryCredentialSetupRequest(
            profileName: "DeveloperID",
            authentication: .appleID(
                appleID: "developer@example.com",
                teamID: "TEAMID1234",
                appSpecificPassword: "abcd-efgh\n-ijkl\r\n-mnop\n"
            )
        )

        let arguments = try CredentialSetupService.storeCredentialsArguments(for: request)

        XCTAssertEqual(arguments.last, "abcd-efgh-ijkl-mnop")
    }

    func testCredentialSetupUsesProcessRunner() async throws {
        let runner = MockProcessRunner()
        let service = CredentialSetupService(runner: runner)
        let request = NotaryCredentialSetupRequest(
            profileName: "DeveloperID",
            authentication: .appleID(
                appleID: "developer@example.com",
                teamID: "TEAMID1234",
                appSpecificPassword: "app-specific-password"
            )
        )

        let result = try await service.storeCredentials(request)

        XCTAssertEqual(result, CredentialSetupResult(profileName: "DeveloperID"))
        XCTAssertEqual(runner.commands.count, 1)
        XCTAssertEqual(runner.commands[0].executableURL.path, "/usr/bin/xcrun")
        XCTAssertEqual(
            runner.commands[0].arguments,
            [
                "notarytool",
                "store-credentials",
                "DeveloperID",
                "--validate",
                "--apple-id",
                "developer@example.com",
                "--team-id",
                "TEAMID1234",
                "--password",
                "app-specific-password"
            ]
        )
        XCTAssertEqual(runner.commands[0].timeout, 300)
    }

    func testCredentialSetupFailureDoesNotExposeAppSpecificPassword() async throws {
        let password = "abcd-efgh-ijkl-mnop"
        let command = ProcessCommand.system(
            "/usr/bin/xcrun",
            [
                "notarytool",
                "store-credentials",
                "DeveloperID",
                "--validate",
                "--apple-id",
                "developer@example.com",
                "--team-id",
                "TEAMID1234",
                "--password",
                password
            ]
        )
        let result = ProcessResult(
            command: command,
            terminationStatus: 69,
            standardOutput: "",
            standardError: "Invalid credentials."
        )
        let runner = MockProcessRunner(error: ProcessRunnerError.nonZeroExit(result))
        let service = CredentialSetupService(runner: runner)
        let request = NotaryCredentialSetupRequest(
            profileName: "DeveloperID",
            authentication: .appleID(
                appleID: "developer@example.com",
                teamID: "TEAMID1234",
                appSpecificPassword: password
            )
        )

        do {
            _ = try await service.storeCredentials(request)
            XCTFail("Expected credential setup to fail.")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Invalid credentials."))
            XCTAssertFalse(error.localizedDescription.contains(password))
        }
    }

    @MainActor
    func testControllerRequiresSuccessfulValidationBeforeBuild() throws {
        let settings = makeSettings()
        let controller = PackagingController(settings: settings)
        let appURL = try makeFixtureApp(displayName: "Fixture App", version: "1.2.3")
        let info = try AppBundleInfo.load(from: appURL)

        controller.selectedAppInfo = info
        controller.outputURL = temporaryDirectory().appendingPathComponent("Fixture.dmg")

        XCTAssertFalse(controller.canBuild)

        controller.validationReport = ValidationReport(appInfo: info, codeSignSummary: "", gatekeeperSummary: "", checkedAt: Date())
        XCTAssertTrue(controller.canBuild)

        controller.isInspectingApp = true
        XCTAssertFalse(controller.canBuild)
    }

    func testNotaryProfileValidationUsesHistoryCommand() async throws {
        let runner = MockProcessRunner()
        let client = NotaryClient(runner: runner)

        try await client.validateKeychainProfile("DeveloperID")

        XCTAssertEqual(runner.commands.count, 1)
        XCTAssertEqual(runner.commands[0].executableURL.path, "/usr/bin/xcrun")
        XCTAssertEqual(
            runner.commands[0].arguments,
            ["notarytool", "history", "--keychain-profile", "DeveloperID", "--output-format", "json"]
        )
        XCTAssertEqual(runner.commands[0].timeout, 60)
    }

    func testNotaryProfileValidationRunsBeforeDmgWork() {
        let stages = PackagingStage.allCases

        XCTAssertLessThan(
            stages.firstIndex(of: .validateNotaryProfile)!,
            stages.firstIndex(of: .stageVolume)!
        )
    }

    func testDmgStagingCopiesAppAndApplicationsSymlink() throws {
        let appURL = try makeFixtureApp(displayName: "Fixture App", version: "1.2.3")
        let info = try AppBundleInfo.load(from: appURL)
        let outputURL = temporaryDirectory().appendingPathComponent("Fixture.dmg")
        let job = PackagingJob(
            appInfo: info,
            outputURL: outputURL,
            volumeName: info.defaultVolumeName,
            signingIdentity: SigningIdentity(hash: "ABC", name: "Developer ID Application: Example"),
            notaryProfile: "DeveloperID",
            replaceExistingOutput: false
        )
        let builder = DmgBuilder(runner: MockProcessRunner())
        let context = try builder.createContext(for: job)

        try builder.stageVolume(job: job, context: context)

        XCTAssertTrue(FileManager.default.fileExists(atPath: context.stagedDirectory.appendingPathComponent("Fixture.app").path))
        let applicationsLink = context.stagedDirectory.appendingPathComponent("Applications")
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: applicationsLink.path), "/Applications")
        let backgroundImage = context.stagedDirectory
            .appendingPathComponent(".background", isDirectory: true)
            .appendingPathComponent("background.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: backgroundImage.path))
        XCTAssertEqual(Array(try Data(contentsOf: backgroundImage).prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
        try? builder.clean(context: context)
    }

    func testFinderLayoutFlushesVolumeMetadataBeforeDetach() async throws {
        let appURL = try makeFixtureApp(displayName: "Fixture App", version: "1.2.3")
        let info = try AppBundleInfo.load(from: appURL)
        let outputURL = temporaryDirectory().appendingPathComponent("Fixture.dmg")
        let job = PackagingJob(
            appInfo: info,
            outputURL: outputURL,
            volumeName: info.defaultVolumeName,
            signingIdentity: SigningIdentity(hash: "ABC", name: "Developer ID Application: Example"),
            notaryProfile: "DeveloperID",
            replaceExistingOutput: false
        )
        let runner = MockProcessRunner()
        let scriptRunner = MockAppleScriptRunner()
        let builder = DmgBuilder(runner: runner, scriptRunner: scriptRunner)
        let context = try builder.createContext(for: job)

        // Simulate Finder writing .DS_Store to the mounted volume when any
        // AppleScript executes. The real Finder writes it when the layout
        // window is closed; writing it on every mock call is a stable
        // substitute that avoids matching against script content.
        let dsStoreURL = context.mountedVolumeURL.appendingPathComponent(".DS_Store")
        scriptRunner.sideEffect = { _ in
            try Data("stub".utf8).write(to: dsStoreURL)
        }

        try await builder.applyFinderLayout(job: job, context: context)

        // Both the probe and the layout script must be sent via NSAppleScript
        // so that Apple Events originate from this process (which holds the
        // user-granted Automation permission) rather than from osascript.
        XCTAssertEqual(scriptRunner.sources.count, 2)
        XCTAssertTrue(scriptRunner.sources[0].contains("name"))              // probe
        XCTAssertTrue(scriptRunner.sources[1].contains("background picture")) // layout

        // sync must precede detach; SetFile failure is non-fatal so its
        // presence in the sequence is not required.
        let paths = runner.commands.map(\.executableURL.path)
        XCTAssertTrue(paths.contains("/usr/bin/hdiutil"))
        XCTAssertTrue(paths.contains("/bin/sync"))
        let syncIndex = paths.firstIndex(of: "/bin/sync")!
        let detachIndex = paths.lastIndex(of: "/usr/bin/hdiutil")!
        XCTAssertLessThan(syncIndex, detachIndex)
        XCTAssertEqual(runner.commands[syncIndex].arguments, [])
        XCTAssertEqual(runner.commands[detachIndex].arguments.first, "detach")
        try? builder.clean(context: context)
    }

    func testDmgContextUsesTemporaryCompressedOutputBeforeFinalPublish() throws {
        let appURL = try makeFixtureApp(displayName: "Fixture App", version: "1.2.3")
        let info = try AppBundleInfo.load(from: appURL)
        let finalOutputURL = temporaryDirectory().appendingPathComponent("Fixture Final.dmg")
        let job = PackagingJob(
            appInfo: info,
            outputURL: finalOutputURL,
            volumeName: info.defaultVolumeName,
            signingIdentity: SigningIdentity(hash: "ABC", name: "Developer ID Application: Example"),
            notaryProfile: "DeveloperID",
            replaceExistingOutput: false
        )
        let builder = DmgBuilder(runner: MockProcessRunner())

        let context = try builder.createContext(for: job)

        XCTAssertEqual(context.finalOutputURL, finalOutputURL)
        XCTAssertEqual(context.compressedImageURL.lastPathComponent, finalOutputURL.lastPathComponent)
        XCTAssertTrue(context.compressedImageURL.path.hasPrefix(context.workDirectory.path))
        XCTAssertNotEqual(context.compressedImageURL, finalOutputURL)
        try? builder.clean(context: context)
    }

    func testPrepareOutputAllowsReplacementWithoutRemovingExistingOutput() throws {
        let builder = DmgBuilder(runner: MockProcessRunner())
        let outputURL = temporaryDirectory().appendingPathComponent("Fixture.dmg")
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "existing".write(to: outputURL, atomically: true, encoding: .utf8)

        try builder.prepareOutput(outputURL, replaceExisting: true)

        XCTAssertEqual(try String(contentsOf: outputURL, encoding: .utf8), "existing")
    }

    func testPublishOutputMovesTemporaryDmgToFinalOutput() throws {
        let appURL = try makeFixtureApp(displayName: "Fixture App", version: "1.2.3")
        let info = try AppBundleInfo.load(from: appURL)
        let finalOutputURL = temporaryDirectory().appendingPathComponent("Fixture.dmg")
        let job = PackagingJob(
            appInfo: info,
            outputURL: finalOutputURL,
            volumeName: info.defaultVolumeName,
            signingIdentity: SigningIdentity(hash: "ABC", name: "Developer ID Application: Example"),
            notaryProfile: "DeveloperID",
            replaceExistingOutput: false
        )
        let builder = DmgBuilder(runner: MockProcessRunner())
        let context = try builder.createContext(for: job)
        try FileManager.default.createDirectory(at: context.compressedImageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: finalOutputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "temporary dmg".write(to: context.compressedImageURL, atomically: true, encoding: .utf8)

        try builder.publishOutput(context: context, replaceExisting: false)

        XCTAssertFalse(FileManager.default.fileExists(atPath: context.compressedImageURL.path))
        XCTAssertEqual(try String(contentsOf: finalOutputURL, encoding: .utf8), "temporary dmg")
        try? builder.clean(context: context)
    }

    func testPublishOutputReplacesExistingFinalOutputAtTheEnd() throws {
        let appURL = try makeFixtureApp(displayName: "Fixture App", version: "1.2.3")
        let info = try AppBundleInfo.load(from: appURL)
        let finalOutputURL = temporaryDirectory().appendingPathComponent("Fixture.dmg")
        let job = PackagingJob(
            appInfo: info,
            outputURL: finalOutputURL,
            volumeName: info.defaultVolumeName,
            signingIdentity: SigningIdentity(hash: "ABC", name: "Developer ID Application: Example"),
            notaryProfile: "DeveloperID",
            replaceExistingOutput: true
        )
        let builder = DmgBuilder(runner: MockProcessRunner())
        let context = try builder.createContext(for: job)
        try FileManager.default.createDirectory(at: context.compressedImageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: finalOutputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "old dmg".write(to: finalOutputURL, atomically: true, encoding: .utf8)
        try "new dmg".write(to: context.compressedImageURL, atomically: true, encoding: .utf8)

        try builder.publishOutput(context: context, replaceExisting: true)

        XCTAssertFalse(FileManager.default.fileExists(atPath: context.compressedImageURL.path))
        XCTAssertEqual(try String(contentsOf: finalOutputURL, encoding: .utf8), "new dmg")
        try? builder.clean(context: context)
    }

    func testFinderLayoutPositionsWindowItems() {
        let script = DmgBuilder(runner: MockProcessRunner(), scriptRunner: MockAppleScriptRunner())
            .debugFinderLayoutScript(appName: "Fixture.app", mountPath: "/tmp/Mounted Fixture")

        XCTAssertTrue(script.contains("set backgroundImageFile to POSIX file \"/tmp/Mounted Fixture/.background/background.png\" as alias"))
        XCTAssertTrue(script.contains("set bounds to {100, 100, 640, 500}"))
        XCTAssertTrue(script.contains("set background picture of iconViewOptions to backgroundImageFile"))
        XCTAssertTrue(script.contains("set icon size of iconViewOptions to 144"))
        XCTAssertTrue(script.contains("set appItem to item \"Fixture.app\" of diskWindow"))
        XCTAssertTrue(script.contains("set applicationsItem to item \"Applications\" of diskWindow"))
        XCTAssertTrue(script.contains("set position of appItem to {140, 175}"))
        XCTAssertTrue(script.contains("set position of applicationsItem to {380, 175}"))
        XCTAssertTrue(script.contains("set text size of iconViewOptions to 12"))
        XCTAssertTrue(script.contains("set label position of iconViewOptions to bottom"))
        XCTAssertTrue(script.contains("open diskFolder"))
        XCTAssertTrue(script.contains("delay 2"))
        XCTAssertFalse(script.contains("set position of item \"Applications\" of diskFolder"))
    }

    private func makeFixtureApp(displayName: String, version: String) throws -> URL {
        let root = temporaryDirectory()
        let appURL = root.appendingPathComponent("Fixture.app", isDirectory: true)
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        let macOSURL = contentsURL.appendingPathComponent("MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: macOSURL, withIntermediateDirectories: true)

        let plist: [String: String] = [
            "CFBundleName": "Fixture",
            "CFBundleDisplayName": displayName,
            "CFBundleIdentifier": "com.example.fixture",
            "CFBundleExecutable": "Fixture",
            "CFBundleShortVersionString": version,
            "CFBundleVersion": "42"
        ]

        let plistData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try plistData.write(to: contentsURL.appendingPathComponent("Info.plist"))

        let executableURL = macOSURL.appendingPathComponent("Fixture")
        try "#!/bin/sh\nexit 0\n".write(to: executableURL, atomically: true, encoding: .utf8)
        chmod(executableURL.path, 0o755)

        return appURL
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("DMGBuildNotarizeTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    @MainActor
    private func makeSettings() -> AppSettings {
        let suiteName = "DMGBuildNotarizeTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let settings = AppSettings(defaults: defaults, signingClient: SigningClient(runner: MockProcessRunner()))
        let identity = SigningIdentity(hash: "ABCDEF1234567890", name: "Developer ID Application: Example Co (TEAMID1234)")
        settings.signingIdentities = [identity]
        settings.signingIdentityHash = identity.hash
        settings.notaryProfile = "DeveloperID"
        return settings
    }
}

private final class MockAppleScriptRunner: AppleScriptRunning, @unchecked Sendable {
    private(set) var sources: [String] = []
    var error: Error?
    var sideEffect: ((String) throws -> Void)?

    func execute(_ source: String) async throws {
        sources.append(source)
        try sideEffect?(source)
        if let error { throw error }
    }
}

private final class MockProcessRunner: ProcessRunning, @unchecked Sendable {
    private(set) var commands: [ProcessCommand] = []
    var result: ProcessResult?
    var results: [ProcessResult]
    var error: Error?

    init(result: ProcessResult? = nil, results: [ProcessResult] = [], error: Error? = nil) {
        self.result = result
        self.results = results
        self.error = error
    }

    func run(_ command: ProcessCommand, onOutput: @escaping @Sendable (String) -> Void) async throws -> ProcessResult {
        commands.append(command)

        if let error {
            throw error
        }

        if !results.isEmpty {
            return results.removeFirst()
        }

        return result ?? ProcessResult(command: command, terminationStatus: 0, standardOutput: "", standardError: "")
    }
}

