import Foundation

struct AppBundleInfo: Identifiable, Equatable {
    var id: String { bundleIdentifier }

    let url: URL
    let displayName: String
    let bundleName: String
    let bundleIdentifier: String
    let shortVersion: String
    let buildVersion: String
    let executableName: String

    var appFileName: String {
        url.lastPathComponent
    }

    var defaultVolumeName: String {
        displayName.sanitizedVolumeName(defaultValue: "Installer")
    }

    var defaultOutputFileName: String {
        let version = shortVersion.sanitizedFileComponent
        let base = displayName.sanitizedFileComponent
        return version.isEmpty ? "\(base).dmg" : "\(base)-\(version).dmg"
    }

    static func load(from appURL: URL) throws -> AppBundleInfo {
        guard appURL.pathExtension == "app" else {
            throw AppBundleInfoError.notAppBundle(appURL.path)
        }

        let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard FileManager.default.fileExists(atPath: plistURL.path) else {
            throw AppBundleInfoError.missingInfoPlist
        }

        let data = try Data(contentsOf: plistURL)
        guard let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            throw AppBundleInfoError.invalidInfoPlist
        }

        let bundleName = nonEmptyString(plist["CFBundleName"]) ?? appURL.deletingPathExtension().lastPathComponent
        let displayName = nonEmptyString(plist["CFBundleDisplayName"]) ?? bundleName

        guard let bundleIdentifier = nonEmptyString(plist["CFBundleIdentifier"]) else {
            throw AppBundleInfoError.missingRequiredKey("CFBundleIdentifier")
        }

        guard let executableName = nonEmptyString(plist["CFBundleExecutable"]) else {
            throw AppBundleInfoError.missingRequiredKey("CFBundleExecutable")
        }

        guard let shortVersion = nonEmptyString(plist["CFBundleShortVersionString"]) else {
            throw AppBundleInfoError.missingRequiredKey("CFBundleShortVersionString")
        }

        let buildVersion = nonEmptyString(plist["CFBundleVersion"]) ?? shortVersion
        let executableURL = appURL.appendingPathComponent("Contents/MacOS/\(executableName)")
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw AppBundleInfoError.missingExecutable(executableName)
        }

        return AppBundleInfo(
            url: appURL,
            displayName: displayName,
            bundleName: bundleName,
            bundleIdentifier: bundleIdentifier,
            shortVersion: shortVersion,
            buildVersion: buildVersion,
            executableName: executableName
        )
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum AppBundleInfoError: LocalizedError, Equatable {
    case notAppBundle(String)
    case missingInfoPlist
    case invalidInfoPlist
    case missingRequiredKey(String)
    case missingExecutable(String)

    var errorDescription: String? {
        switch self {
        case .notAppBundle(let path):
            return "Expected a .app bundle, but got \(path)."
        case .missingInfoPlist:
            return "The app bundle is missing Contents/Info.plist."
        case .invalidInfoPlist:
            return "The app bundle has an unreadable Info.plist."
        case .missingRequiredKey(let key):
            return "The app bundle Info.plist is missing \(key)."
        case .missingExecutable(let executable):
            return "The app bundle executable \(executable) is missing or is not executable."
        }
    }
}
