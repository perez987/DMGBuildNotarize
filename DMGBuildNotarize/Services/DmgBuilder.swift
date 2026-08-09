import AppKit
import Foundation

struct DmgBuildContext: Equatable {
    let workDirectory: URL
    let stagedDirectory: URL
    let readWriteImageURL: URL
    let compressedImageURL: URL
    let finalOutputURL: URL
    let mountedVolumeURL: URL
}

struct DmgBuilder: @unchecked Sendable {
    // MARK: - FinderLayout constants

    private enum FinderLayout {
        static let windowOriginX = 100
        static let windowOriginY = 100
        static let backgroundWidth = 540
        static let backgroundHeight = 400
        static let iconSize = 144
        static let textSize = 12
        static let appPositionX = 140
        static let appPositionY = 175
        static let applicationsPositionX = 380
        static let applicationsPositionY = 175
        static let backgroundDirectoryName = ".background"
        static let bundledBackgroundDirectoryName = "Background"
        static let backgroundFileBaseName = "background"
        static let backgroundFileExtension = "png"
        static let backgroundFileName = "background.png"
        static let backgroundTopInset: CGFloat = 36
        static let backgroundCornerRadius: CGFloat = 18
        static let arrowLineWidth: CGFloat = 18
        static let arrowHeadLength: CGFloat = 28
        static let arrowHeadHalfHeight: CGFloat = 18

        static var windowRight: Int { windowOriginX + backgroundWidth }
        static var windowBottom: Int { windowOriginY + backgroundHeight }
        static var backgroundSize: NSSize { NSSize(width: CGFloat(backgroundWidth), height: CGFloat(backgroundHeight)) }
    }

    let runner: any ProcessRunning
    let scriptRunner: any AppleScriptRunning
    nonisolated(unsafe) let fileManager: FileManager

    nonisolated init(
        runner: any ProcessRunning = ProcessRunner(),
        scriptRunner: any AppleScriptRunning = DefaultAppleScriptRunner(),
        fileManager: FileManager = .default
    ) {
        self.runner = runner
        self.scriptRunner = scriptRunner
        self.fileManager = fileManager
    }

    func createContext(for job: PackagingJob) throws -> DmgBuildContext {
        let base = fileManager.temporaryDirectory
            .appendingPathComponent("DMGBuildNotarize", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let volumeName = job.volumeName.sanitizedVolumeName(defaultValue: job.appInfo.defaultVolumeName)
        return DmgBuildContext(
            workDirectory: base,
            stagedDirectory: base.appendingPathComponent("stage", isDirectory: true),
            readWriteImageURL: base.appendingPathComponent("\(volumeName).rw.dmg"),
            compressedImageURL: base.appendingPathComponent(job.outputURL.lastPathComponent),
            finalOutputURL: job.outputURL,
            mountedVolumeURL: base.appendingPathComponent("mount", isDirectory: true)
        )
    }

    func prepareOutput(_ outputURL: URL, replaceExisting: Bool) throws {
        guard outputURL.hasReachableDirectoryParent else {
            throw DmgBuilderError.outputDirectoryMissing(outputURL.deletingLastPathComponent().path)
        }

        guard fileManager.fileExists(atPath: outputURL.path) else { return }
        guard replaceExisting else {
            throw DmgBuilderError.outputAlreadyExists(outputURL.path)
        }
    }

    func stageVolume(job: PackagingJob, context: DmgBuildContext) throws {
        try clean(context: context)
        try fileManager.createDirectory(at: context.stagedDirectory, withIntermediateDirectories: true)

        let appDestination = context.stagedDirectory.appendingPathComponent(job.appInfo.appFileName, isDirectory: true)
        try fileManager.copyItem(at: job.appInfo.url, to: appDestination)

        let applicationsAlias = context.stagedDirectory.appendingPathComponent("Applications")
        try fileManager.createSymbolicLink(at: applicationsAlias, withDestinationURL: URL(fileURLWithPath: "/Applications", isDirectory: true))

        let backgroundDirectory = context.stagedDirectory.appendingPathComponent(FinderLayout.backgroundDirectoryName, isDirectory: true)
        try fileManager.createDirectory(at: backgroundDirectory, withIntermediateDirectories: true)
        try installBackgroundImage(at: backgroundDirectory.appendingPathComponent(FinderLayout.backgroundFileName))
    }

    func createReadWriteImage(job: PackagingJob, context: DmgBuildContext, onOutput: @escaping @Sendable (String) -> Void = { _ in }) async throws {
        try await runner.run(
            .system(
                "/usr/bin/hdiutil",
                [
                    "create",
                    "-volname", job.volumeName,
                    "-srcfolder", context.stagedDirectory.path,
                    "-ov",
                    "-format", "UDRW",
                    context.readWriteImageURL.path
                ]
            ),
            onOutput: onOutput
        )
    }

    func applyFinderLayout(job: PackagingJob, context: DmgBuildContext, onOutput: @escaping @Sendable (String) -> Void = { _ in }) async throws {
        try fileManager.createDirectory(at: context.mountedVolumeURL, withIntermediateDirectories: true)

        // Activate the app before scripting Finder so that the process is
        // treated as a foreground caller.
        await activateCurrentApplication()

        // Probe Finder automation using NSAppleScript so that Apple Events are
        // sent from DMGBuildNotarize (which holds the user-granted Automation
        // permission) rather than from a subsidiary osascript child process that
        // may not share that permission. This surfaces any Automation denial as
        // a clear error before the volume is mounted.
        try await scriptRunner.execute(finderPermissionProbeScript())

        do {
            try await runner.run(
                .system(
                    "/usr/bin/hdiutil",
                    [
                        "attach",
                        context.readWriteImageURL.path,
                        "-readwrite",
                        "-noverify",
                        "-noautoopen",
                        "-mountpoint",
                        context.mountedVolumeURL.path
                    ]
                ),
                onOutput: onOutput
            )

            try await scriptRunner.execute(
                finderLayoutScript(appName: job.appInfo.appFileName, mountPath: context.mountedVolumeURL.path)
            )

            // Verify that Finder persisted the window layout to .DS_Store on
            // the mounted volume. If not present within the timeout the DMG
            // would be silently unstyled; throw a clear, actionable error.
            try await waitForDSStore(at: context.mountedVolumeURL, onOutput: onOutput)

            // Set the custom-icon attribute on the volume root. This is
            // cosmetic (affects the folder icon on the desktop) so a missing
            // or failed SetFile is logged but not treated as fatal.
            do {
                try await runner.run(
                    .system("/usr/bin/SetFile", ["-a", "C", context.mountedVolumeURL.path]),
                    onOutput: onOutput
                )
            } catch {
                onOutput("Warning: could not set custom-icon attribute: \(error.localizedDescription)")
            }

            try await runner.run(.system("/bin/sync", []), onOutput: onOutput)
        } catch {
            try? await detachMountedVolume(context: context, force: true, onOutput: onOutput)
            await activateCurrentApplication()
            throw error
        }

        try await detachMountedVolume(context: context, force: false, onOutput: onOutput)
        await activateCurrentApplication()
    }

    func convertCompressedImage(context: DmgBuildContext, onOutput: @escaping @Sendable (String) -> Void = { _ in }) async throws {
        try await runner.run(
            .system(
                "/usr/bin/hdiutil",
                [
                    "convert",
                    context.readWriteImageURL.path,
                    "-format",
                    "UDZO",
                    "-imagekey",
                    "zlib-level=9",
                    "-o",
                    context.compressedImageURL.path
                ]
            ),
            onOutput: onOutput
        )
    }

    func verifyImage(_ dmgURL: URL, onOutput: @escaping @Sendable (String) -> Void = { _ in }) async throws {
        try await runner.run(.system("/usr/bin/hdiutil", ["verify", dmgURL.path]), onOutput: onOutput)
    }

    func publishOutput(context: DmgBuildContext, replaceExisting: Bool) throws {
        guard context.finalOutputURL.hasReachableDirectoryParent else {
            throw DmgBuilderError.outputDirectoryMissing(context.finalOutputURL.deletingLastPathComponent().path)
        }

        guard fileManager.fileExists(atPath: context.finalOutputURL.path) else {
            try fileManager.moveItem(at: context.compressedImageURL, to: context.finalOutputURL)
            return
        }

        guard replaceExisting else {
            throw DmgBuilderError.outputAlreadyExists(context.finalOutputURL.path)
        }

        _ = try fileManager.replaceItemAt(
            context.finalOutputURL,
            withItemAt: context.compressedImageURL,
            backupItemName: nil,
            options: []
        )
    }

    func clean(context: DmgBuildContext) throws {
        if fileManager.fileExists(atPath: context.workDirectory.path) {
            try fileManager.removeItem(at: context.workDirectory)
        }
    }

    private func detachMountedVolume(context: DmgBuildContext, force: Bool, onOutput: @escaping @Sendable (String) -> Void) async throws {
        var arguments = ["detach", context.mountedVolumeURL.path]
        if force {
            arguments.append("-force")
        }
        try await runner.run(.system("/usr/bin/hdiutil", arguments), onOutput: onOutput)
    }

    private func activateCurrentApplication() async {
        await MainActor.run {
            NSApplication.shared.activate()
        }
    }

    /// Polls until `.DS_Store` appears on the mounted volume or the timeout
    /// expires. Finder writes this file after closing the window; we must wait
    /// for it before syncing and detaching so the layout is preserved in the
    /// compressed image.
    private func waitForDSStore(at volumeURL: URL, onOutput: @escaping @Sendable (String) -> Void) async throws {
        let dsStoreURL = volumeURL.appendingPathComponent(".DS_Store")
        let deadline = Date().addingTimeInterval(10)

        while !fileManager.fileExists(atPath: dsStoreURL.path) {
            guard Date() < deadline else {
                throw DmgBuilderError.finderLayoutNotPersisted
            }
            onOutput("Waiting for Finder to write .DS_Store to the volume…")
            try await Task.sleep(for: .milliseconds(500))
        }

        onOutput("Finder layout persisted to .DS_Store.")
    }

    private func finderPermissionProbeScript() -> String {
        // A trivial read-only query that will fail with an Automation denied
        // error (-1743) if DMGBuildNotarize does not have permission to control
        // Finder. Because we run this via NSAppleScript in our own process, the
        // TCC check is against DMGBuildNotarize—the app the user sees in System
        // Settings › Privacy & Security › Automation—not against a subsidiary
        // osascript child process.
        """
        tell application "Finder" to name
        """
    }

    private func finderLayoutScript(appName: String, mountPath: String) -> String {
        let backgroundPath = URL(fileURLWithPath: mountPath, isDirectory: true)
            .appendingPathComponent(FinderLayout.backgroundDirectoryName, isDirectory: true)
            .appendingPathComponent(FinderLayout.backgroundFileName)
            .path

        // Open the window and apply all layout settings in a single NSAppleScript
        // invocation so there is no race between two separate calls.
        //
        // The post-close delay is 5 seconds (up from 1.5 s) because macOS Tahoe's
        // redesigned Finder writes .DS_Store more asynchronously after a window
        // closes. waitForDSStore() polls for up to 10 additional seconds and throws
        // a clear error if the file still does not appear, so 5 s represents an
        // empirical minimum rather than a hard upper bound.
        return """
        tell application "Finder"
            set diskFolder to POSIX file \(mountPath.debugDescription) as alias
            open diskFolder
            delay 2
            set diskWindow to container window of diskFolder
            set backgroundImageFile to POSIX file \(backgroundPath.debugDescription) as alias
            tell diskWindow
                set current view to icon view
                set toolbar visible to false
                set statusbar visible to false
                set bounds to {\(FinderLayout.windowOriginX), \(FinderLayout.windowOriginY), \(FinderLayout.windowRight), \(FinderLayout.windowBottom)}
            end tell
            set iconViewOptions to icon view options of diskWindow
            set arrangement of iconViewOptions to not arranged
            set background picture of iconViewOptions to backgroundImageFile
            set icon size of iconViewOptions to \(FinderLayout.iconSize)
            set text size of iconViewOptions to \(FinderLayout.textSize)
            set label position of iconViewOptions to bottom
            set appItem to item \(appName.debugDescription) of diskWindow
            set applicationsItem to item "Applications" of diskWindow
            set position of appItem to {\(FinderLayout.appPositionX), \(FinderLayout.appPositionY)}
            set position of applicationsItem to {\(FinderLayout.applicationsPositionX), \(FinderLayout.applicationsPositionY)}
            update diskFolder without registering applications
            delay 2
            close diskWindow
            delay 5
        end tell
        """
    }

    // MARK: - Background image installation

    private func installBackgroundImage(at destinationURL: URL) throws {
        if let sourceURL = bundledBackgroundImageURL() {
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            return
        }

        try createBackgroundImage(at: destinationURL)
    }

    private func bundledBackgroundImageURL() -> URL? {
        let bundles = [Bundle.main, Bundle(for: BundleLocator.self)]
        for bundle in bundles {
            if let url = bundle.url(
                forResource: FinderLayout.backgroundFileBaseName,
                withExtension: FinderLayout.backgroundFileExtension,
                subdirectory: FinderLayout.bundledBackgroundDirectoryName
            ) {
                return url
            }

            if let url = bundle.url(
                forResource: FinderLayout.backgroundFileBaseName,
                withExtension: FinderLayout.backgroundFileExtension
            ) {
                return url
            }
        }

        return nil
    }

    private func createBackgroundImage(at url: URL) throws {
        let imageSize = FinderLayout.backgroundSize
        let width = Int(imageSize.width)
        let height = Int(imageSize.height)

        guard
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let cgContext = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            throw CocoaError(.fileWriteUnknown)
        }

        let nsContext = NSGraphicsContext(cgContext: cgContext, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsContext
        defer { NSGraphicsContext.restoreGraphicsState() }

        NSColor(calibratedWhite: 0.97, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: imageSize)).fill()

        NSGradient(
            colors: [
                NSColor(calibratedRed: 0.43, green: 0.67, blue: 0.98, alpha: 1),
                NSColor(calibratedRed: 0.23, green: 0.43, blue: 0.89, alpha: 1)
            ]
        )?.draw(
            in: NSRect(
                x: 0,
                y: imageSize.height - FinderLayout.backgroundTopInset - 96,
                width: imageSize.width,
                height: 96 + FinderLayout.backgroundTopInset
            ),
            angle: 90
        )

        let cardRect = NSRect(
            x: 28,
            y: 28,
            width: imageSize.width - 56,
            height: imageSize.height - FinderLayout.backgroundTopInset - 56
        )
        NSColor.white.withAlphaComponent(0.9).setFill()
        NSBezierPath(roundedRect: cardRect, xRadius: FinderLayout.backgroundCornerRadius, yRadius: FinderLayout.backgroundCornerRadius).fill()

        let leftPoint = NSPoint(x: 218, y: 185)
        let rightPoint = NSPoint(x: 322, y: 185)
        NSColor(calibratedRed: 0.20, green: 0.48, blue: 0.92, alpha: 0.95).setStroke()
        let arrow = NSBezierPath()
        arrow.lineWidth = FinderLayout.arrowLineWidth
        arrow.lineCapStyle = .round
        arrow.move(to: leftPoint)
        arrow.line(to: rightPoint)
        arrow.stroke()

        let arrowHead = NSBezierPath()
        arrowHead.lineWidth = FinderLayout.arrowLineWidth
        arrowHead.lineCapStyle = .round
        arrowHead.move(to: NSPoint(x: rightPoint.x - FinderLayout.arrowHeadLength, y: rightPoint.y + FinderLayout.arrowHeadHalfHeight))
        arrowHead.line(to: rightPoint)
        arrowHead.line(to: NSPoint(x: rightPoint.x - FinderLayout.arrowHeadLength, y: rightPoint.y - FinderLayout.arrowHeadHalfHeight))
        arrowHead.stroke()

        drawBackgroundText(
            "Drag to Applications",
            in: NSRect(x: 138, y: 110, width: 264, height: 34),
            font: .systemFont(ofSize: 24, weight: .semibold),
            color: NSColor(calibratedWhite: 0.22, alpha: 0.95)
        )

        drawBackgroundText(
            "Install the app by dragging it onto the Applications shortcut.",
            in: NSRect(x: 110, y: 78, width: 320, height: 18),
            font: .systemFont(ofSize: 13, weight: .regular),
            color: NSColor(calibratedWhite: 0.40, alpha: 1)
        )

        guard let cgImage = cgContext.makeImage() else {
            throw CocoaError(.fileWriteUnknown)
        }

        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }

        try pngData.write(to: url, options: .atomic)
    }

    private func drawBackgroundText(_ text: String, in rect: NSRect, font: NSFont, color: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        text.draw(
            in: rect,
            withAttributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ]
        )
    }
}

private final class BundleLocator {}

#if DEBUG
extension DmgBuilder {
    func debugFinderLayoutScript(appName: String, mountPath: String) -> String {
        finderLayoutScript(appName: appName, mountPath: mountPath)
    }
}
#endif

enum DmgBuilderError: LocalizedError, Equatable {
    case outputDirectoryMissing(String)
    case outputAlreadyExists(String)
    case finderLayoutNotPersisted

    var errorDescription: String? {
        switch self {
        case .outputDirectoryMissing(let path):
            return "The output directory does not exist: \(path)"
        case .outputAlreadyExists(let path):
            return "The output file already exists: \(path)"
        case .finderLayoutNotPersisted:
            return """
            Finder did not write the DMG window layout to disk. \
            Confirm that DMGBuildNotarize has permission to control Finder \
            in System Settings › Privacy & Security › Automation, then try again.
            """
        }
    }
}
