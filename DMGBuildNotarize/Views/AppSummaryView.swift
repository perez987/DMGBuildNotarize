import SwiftUI

struct AppSummaryView: View {
    let info: AppBundleInfo?
    let report: ValidationReport?

    var body: some View {
        GroupBox("") {
            if let info {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                    SummaryRow("Name", info.displayName)
                    SummaryRow("Bundle ID", info.bundleIdentifier)
                    SummaryRow("Version", "\(info.shortVersion) (\(info.buildVersion))")
                    SummaryRow("Executable", info.executableName)
                    SummaryRow("Signature", report == nil ? String(localized: "Checking") : String(localized: "Developer ID ready"))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "app.badge")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("No App Selected")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 130)
            }
        }
    }
}

private struct SummaryRow: View {
    let title: LocalizedStringKey
    let value: String

    init(_ title: LocalizedStringKey, _ value: String) {
        self.title = title
        self.value = value
    }

    var body: some View {
        GridRow {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

