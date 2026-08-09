import SwiftUI

@main
struct DMGBuildNotarizeApp: App {
    @StateObject private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            ContentView(settings: settings)
                .frame(minWidth: 832, idealWidth: 832, maxWidth: 832, minHeight: 640)
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView(settings: settings)
                .frame(width: 620)
        }
    }
}
