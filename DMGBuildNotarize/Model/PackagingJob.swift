import Foundation

struct PackagingJob: Equatable {
    let appInfo: AppBundleInfo
    let outputURL: URL
    let volumeName: String
    let signingIdentity: SigningIdentity
    let notaryProfile: String
    let replaceExistingOutput: Bool
}

struct PackagingResult: Equatable {
    let outputURL: URL
    let notarizationID: String?
}

