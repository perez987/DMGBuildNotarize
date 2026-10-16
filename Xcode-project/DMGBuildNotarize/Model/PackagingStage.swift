import Foundation

enum PackagingStage: String, CaseIterable, Identifiable {
    case validateApp
    case validateNotaryProfile
    case stageVolume
    case createReadWriteImage
    case applyFinderLayout
    case convertCompressedImage
    /// Used when `create-dmg` is installed. Replaces the four AppleScript-based
    /// stages above with a single polished-DMG build step.
    case buildDMG
    case signDMG
    case notarize
    case staple
    case verify

    var id: String { rawValue }

    var title: String {
        switch self {
        case .validateApp: return String(localized: "Validate app")
        case .validateNotaryProfile: return String(localized: "Validate notary profile")
        case .stageVolume: return String(localized: "Stage installer")
        case .createReadWriteImage: return String(localized: "Create writable DMG")
        case .applyFinderLayout: return String(localized: "Apply Finder layout")
        case .convertCompressedImage: return String(localized: "Compress DMG")
        case .buildDMG: return String(localized: "Build DMG")
        case .signDMG: return String(localized: "Sign DMG")
        case .notarize: return String(localized: "Notarize")
        case .staple: return String(localized: "Staple ticket")
        case .verify: return String(localized: "Verify")
        }
    }
}

enum StageState: Equatable {
    case pending
    case running
    case succeeded
    case failed(String)
}

struct StageProgress: Identifiable, Equatable {
    let stage: PackagingStage
    var state: StageState

    var id: PackagingStage { stage }
}
