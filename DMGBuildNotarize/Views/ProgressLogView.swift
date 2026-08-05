import SwiftUI

struct ProgressLogView: View {
    let logText: String
    let errorMessage: String?
    let credentialSetupProfileName: String?
    let result: PackagingResult?
    let onCreateCredentialProfile: () -> Void

    var body: some View {
        GroupBox("Log") {
            VStack(alignment: .leading, spacing: 10) {
                if let errorMessage {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.body)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)

                        if let credentialSetupProfileName {
                            Button {
                                onCreateCredentialProfile()
                            } label: {
                                Label("Create \(credentialSetupProfileName) Profile", systemImage: "key")
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                } else if let result {
                    Label(result.outputURL.path, systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .textSelection(.enabled)
                }

                ScrollView {
                    Text(logText.isEmpty ? String(localized: "Command output will appear here.") : logText)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(logText.isEmpty ? .secondary : .primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(minHeight: 200)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.secondary.opacity(0.18))
                }
            }
        }
    }
}
