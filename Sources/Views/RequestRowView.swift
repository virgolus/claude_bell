import SwiftUI

struct RequestRowView: View {
    let request: PendingRequest

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: ToolIconMapper.icon(for: request.toolName))
                .foregroundStyle(.orange)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(request.toolName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)

                Text(request.projectName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(TimeAgoFormatter.format(request.createdAt))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}
