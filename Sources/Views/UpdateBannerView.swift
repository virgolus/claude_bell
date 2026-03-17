import SwiftUI

struct UpdateBannerView: View {
    let update: UpdateChecker.UpdateInfo
    @EnvironmentObject var store: RequestStore
    @StateObject private var checker = UpdateChecker()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "arrow.up.circle.fill")
                    .foregroundStyle(.blue)
                Text("Update available: v\(update.version)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }

            Text(update.highlights)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 8) {
                Button {
                    Task { await checker.downloadAndInstall() }
                } label: {
                    if checker.isDownloading {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.horizontal, 4)
                    } else {
                        Text("Update Now")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(checker.isDownloading)

                Button("Dismiss") {
                    AppDefaults.shared.set(update.build, forKey: "dismissedUpdateBuild")
                    store.availableUpdate = nil
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(checker.isDownloading)
            }

            if let error = checker.downloadError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(10)
        .background(.blue.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 12)
        .padding(.top, 6)
    }
}
