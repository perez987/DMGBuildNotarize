import AppKit

/// Executes an AppleScript from the calling process so that the Automation
/// TCC permission granted to DMGBuildNotarize—rather than to a subsidiary
/// `osascript` child process—is used when sending Apple Events to Finder.
protocol AppleScriptRunning: Sendable {
    func execute(_ source: String) async throws
}

/// Runs AppleScript on a dedicated serial background queue via `NSAppleScript`.
///
/// Using a dedicated serial queue keeps `NSAppleScript` off the main thread
/// while guaranteeing it is never executed concurrently (`NSAppleScript` is
/// not thread-safe).
struct DefaultAppleScriptRunner: AppleScriptRunning {
    nonisolated init() {}

    private static let queue = DispatchQueue(
        label: "DMGBuildNotarize.applescript",
        qos: .userInitiated
    )

    func execute(_ source: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Self.queue.async {
                guard let script = NSAppleScript(source: source) else {
                    continuation.resume(throwing: AppleScriptError.compilationFailed)
                    return
                }
                var errorInfo: NSDictionary?
                _ = script.executeAndReturnError(&errorInfo)

                // Recent SDKs import executeAndReturnError's result as
                // non-optional. On failure it returns a null descriptor, so
                // checking the result against nil can never detect the error.
                // Detect error via the error dictionary instead.
                if let errorInfo {
                    let message = errorInfo[NSAppleScript.errorMessage] as? String
                        ?? "Unknown AppleScript error"
                    let code = (errorInfo[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? -1
                    continuation.resume(throwing: NSError(
                        domain: "NSAppleScript",
                        code: code,
                        userInfo: [NSLocalizedDescriptionKey: message]
                    ))
                } else {
                    continuation.resume()
                }
            }
        }
    }
}

enum AppleScriptError: LocalizedError {
    case compilationFailed

    var errorDescription: String? {
        "Failed to compile AppleScript source."
    }
}
