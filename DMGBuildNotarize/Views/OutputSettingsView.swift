import AppKit
import SwiftUI

struct OutputSettingsView: View {
    @ObservedObject var controller: PackagingController

    var body: some View {
        GroupBox("DMG") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Volume")
                        .foregroundStyle(.secondary)
                    TextField("Volume name", text: $controller.volumeName)
                        .textFieldStyle(.roundedBorder)
                }

                GridRow {
                    Text("Output")
                        .foregroundStyle(.secondary)
                    HStack {
                        Text(controller.outputURL?.path ?? String(localized: "Choose output"))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)

                        Spacer()

                        Button {
                            chooseOutput()
                        } label: {
                            Image(systemName: "folder")
                        }
                        .help("Choose Output")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func chooseOutput() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.diskImage]
        panel.nameFieldStringValue = controller.outputURL?.lastPathComponent ?? "Installer.dmg"
        if let directory = controller.outputURL?.deletingLastPathComponent() {
            panel.directoryURL = directory
        }

        if panel.runModal() == .OK, let url = panel.url {
            controller.chooseOutput(url: url)
        }
    }
}
