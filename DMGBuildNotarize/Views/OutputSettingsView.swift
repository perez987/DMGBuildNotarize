import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct OutputSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var controller: PackagingController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "DMG"))
                .font(.headline.weight(.semibold))
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
        .padding(16)
        .glassCard(colorScheme: colorScheme, cornerRadius: 20, accentOpacity: 0.18)
    }

    private func chooseOutput() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.diskImage]
        panel.nameFieldStringValue = controller.outputURL?.lastPathComponent ?? "Image.dmg"
        if let directory = controller.outputURL?.deletingLastPathComponent() {
            panel.directoryURL = directory
        }

        if panel.runModal() == .OK, let url = panel.url {
            controller.chooseOutput(url: url)
        }
    }
}
