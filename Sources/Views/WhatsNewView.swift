import SwiftUI

struct WhatsNewView: View {
    let releases: [ChangelogRelease]
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 32))
                    .foregroundStyle(.orange)
                Text("What's New")
                    .font(.title.bold())
                if let first = releases.first {
                    Text("Version \(first.version)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 24)
            .padding(.bottom, 16)

            Divider()

            // Changes list
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(releases, id: \.version) { release in
                        releaseSection(release)
                    }
                }
                .padding(20)
            }

            Divider()

            // Footer
            Button(action: onDismiss) {
                Text("Continue")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .padding(16)
        }
        .frame(width: 420, height: 460)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
    }

    private func releaseSection(_ release: ChangelogRelease) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if releases.count > 1 {
                HStack(spacing: 8) {
                    Text("v\(release.version)")
                        .font(.headline)
                    Text(release.date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(release.highlights)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(release.changes) { change in
                    changeRow(change)
                }
            }
        }
    }

    private func changeRow(_ change: ChangelogChange) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(change.type.label)
                .font(.caption2.weight(.bold))
                .textCase(.uppercase)
                .foregroundStyle(change.type.color)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(change.type.color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .frame(width: 72, alignment: .leading)

            Text(change.text)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

extension ChangelogChange.ChangeType {
    var label: String {
        switch self {
        case .new: "New"
        case .changed: "Changed"
        case .fixed: "Fixed"
        case .removed: "Removed"
        }
    }

    var color: Color {
        switch self {
        case .new: .green
        case .changed: .blue
        case .fixed: .orange
        case .removed: .red
        }
    }
}
