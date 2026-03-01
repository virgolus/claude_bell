import SwiftUI

struct NotificationRowView: View {
    let notification: NotificationEntry

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: notification.meta.rowIcon)
                .foregroundStyle(notification.meta.iconColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(notification.displayTitle)
                    .font(.body.weight(.medium))
                    .lineLimit(1)

                Text(notification.projectName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(TimeAgoFormatter.format(notification.createdAt))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}
