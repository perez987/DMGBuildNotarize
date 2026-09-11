import SwiftUI

struct ProgressLogView: View {
    struct RenderState: Equatable {
        let bodyText: String?
        let showsPlaceholder: Bool
        let warningMessage: String?
        let successPath: String?
    }

    private let bottomAnchorID = "progress-log-bottom-anchor"
    @Environment(\.colorScheme) private var colorScheme
    let logText: String
    let errorMessage: String?
    let credentialSetupProfileName: String?
    let result: PackagingResult?
    let onCreateCredentialProfile: () -> Void

    var renderState: RenderState {
        let showsPlaceholder = logText.isEmpty && errorMessage == nil && result == nil
        return RenderState(
            bodyText: showsPlaceholder ? String(localized: "Command output will appear here.") : (logText.isEmpty ? nil : logText),
            showsPlaceholder: showsPlaceholder,
            warningMessage: errorMessage,
            successPath: result?.outputURL.path
        )
    }

    private func scrollToBottom(using proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.15)) {
            proxy.scrollTo(bottomAnchorID, anchor: .bottom)
        }
    }

    var body: some View {
        let renderState = renderState

        VStack(alignment: .leading, spacing: 10) {
            Text("Log")
                .font(.headline.weight(.semibold))

            if errorMessage != nil, let credentialSetupProfileName {
                Button {
                    onCreateCredentialProfile()
                } label: {
                    Label(
                        String(format: String(localized: "Create %@ Profile"), credentialSetupProfileName),
                        systemImage: "key"
                    )
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if let bodyText = renderState.bodyText {
                            Text(bodyText)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(renderState.showsPlaceholder ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary.opacity(0.96)))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                        }

                        if let errorMessage = renderState.warningMessage {
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(String(localized: "Warning") + ":")
                                    Text(errorMessage)
                                }
                            }
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.red)
                                .textSelection(.enabled)
                                .accessibilityElement(children: .combine)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.bottom, 12)
                        }

                        if let successPath = renderState.successPath {
                            Label(successPath, systemImage: "checkmark.seal.fill")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.blue)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.bottom, 12)
                        }

                        Color.clear
                            .frame(height: 1)
                            .id(bottomAnchorID)
                    }
                }
                .onChange(of: errorMessage) { oldValue, newValue in
                    guard oldValue != newValue, newValue != nil else { return }
                    scrollToBottom(using: proxy)
                }
                .onChange(of: logText) { oldValue, newValue in
                    guard newValue.count > oldValue.count else { return }
                    scrollToBottom(using: proxy)
                }
                .onChange(of: result?.outputURL.path) { oldValue, newValue in
                    guard oldValue != newValue, newValue != nil else { return }
                    scrollToBottom(using: proxy)
                }
                .onAppear {
                    scrollToBottom(using: proxy)
                }
            }
            .frame(minHeight: 196, idealHeight: 196, maxHeight: 196)
            .background(AppTheme.logBackground(for: colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(AppTheme.borderGradient(for: colorScheme), lineWidth: 1)
            }
        }
        .padding(16)
        .glassCard(colorScheme: colorScheme, cornerRadius: 20, accentOpacity: 0.16)
    }
}
