import Darwin
import Foundation

/// Wraps the Node.js `create-dmg` command-line tool.
///
/// `create-dmg` builds a polished installer DMG from a `.app` bundle without
/// requiring Automation (AppleScript) permission or Finder interaction. It is
/// faster and more reliable than the AppleScript-based Finder layout approach.
///
/// When `create-dmg` is installed, `PackagingPipeline` uses it in place of
/// the four-step AppleScript flow (stage volume → writable DMG → Finder layout
/// → compress). When it is not installed the pipeline falls back to AppleScript.
///
/// Install with npm:
/// ```
/// npm install --global create-dmg
/// ```
struct CreateDmgRunner: @unchecked Sendable {
    let runner: any ProcessRunning

    /// Standard installation paths checked on Intel and Apple Silicon Macs.
    static let installationCandidates: [String] = [
        "/usr/local/bin/create-dmg",    // Intel Homebrew / npm global
        "/opt/homebrew/bin/create-dmg"  // Apple Silicon Homebrew
    ]

    /// Returns the path to `create-dmg` if it is installed, or `nil`.
    nonisolated static func findCreateDmg() -> String? {
        installationCandidates.first { access($0, X_OK) == 0 }
    }

    /// Runs `create-dmg <appPath> <outputFolder>` and streams output via `onOutput`.
    ///
    /// `create-dmg` writes a polished, styled `.dmg` directly into `outputFolder`.
    /// The output file is typically named `<AppName> <Version>.dmg`.
    func run(
        appURL: URL,
        outputFolder: URL,
        onOutput: @escaping @Sendable (String) -> Void = { _ in }
    ) async throws {
        guard let path = Self.findCreateDmg() else {
            throw CreateDmgError.notFound
        }

        // Extend PATH so create-dmg can resolve its own Node.js dependencies at
        // the same Homebrew prefix where it was installed.
        let existingPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let extraDirs = Self.installationCandidates.map {
            URL(fileURLWithPath: $0).deletingLastPathComponent().path
        }
        let extendedPath = (extraDirs + [existingPath]).joined(separator: ":")

        var command = ProcessCommand.system(path, [appURL.path, outputFolder.path])
        command.environment["PATH"] = extendedPath

        try await runner.run(command, onOutput: onOutput)
    }

    /// Returns the most recently created `.dmg` inside `folder`.
    ///
    /// After `create-dmg` finishes, the resulting DMG is the newest `.dmg` in
    /// the output directory. Sorting by creation date picks it up reliably even
    /// if the exact name varies by app version.
    static func findResultingDMG(in folder: URL) -> URL? {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ) else { return nil }

        return items
            .filter { $0.pathExtension.lowercased() == "dmg" }
            .sorted { a, b in
                let dateA = (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let dateB = (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return dateA > dateB
            }
            .first
    }
}

enum CreateDmgError: LocalizedError {
    case notFound
    case dmgNotFound

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "create-dmg not found. Install it with: npm install --global create-dmg"
        case .dmgNotFound:
            return "create-dmg did not produce a DMG file in the expected output folder."
        }
    }
}
