import SwiftUI

struct NotificationRowView: View {
    let notification: NotificationEntry

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: notificationIcon)
                .foregroundStyle(.blue)
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

    private var notificationIcon: String {
        switch notification.notificationType {
        case "permission_prompt": return "lock.shield"
        case "idle_prompt": return "questionmark.circle"
        case "elicitation_dialog": return "text.bubble"
        case "stop": return "checkmark.circle"
        default: return "bell"
        }
    }
}
