import SwiftUI

struct SessionRowView: View {
    let session: SessionInfo

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(.green)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.displayName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)

                if session.customName != nil {
                    Text(session.projectName)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else {
                    Text(session.id.prefix(8) + "...")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Text(TimeAgoFormatter.format(session.lastSeen))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}
