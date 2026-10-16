import Foundation

extension URL {
    var hasReachableDirectoryParent: Bool {
        let parent = deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: parent.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
