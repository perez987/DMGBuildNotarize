import SwiftUI

@main
struct DMGBuildNotarizeApp: App {
    @StateObject private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            ContentView(settings: settings)
                .frame(minWidth: 750, idealWidth: 750, maxWidth: 750, minHeight: 722, idealHeight: 722, maxHeight: 722)
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView(settings: settings)
                .frame(width: 620)
                .frame(height: 550)
        }
    }
}
