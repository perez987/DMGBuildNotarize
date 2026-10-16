import Foundation

struct ValidationReport: Equatable {
    let appInfo: AppBundleInfo
    let codeSignSummary: String
    let gatekeeperSummary: String
    let checkedAt: Date
}

