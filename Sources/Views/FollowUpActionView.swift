import SwiftUI

struct FollowUpActionView: View {
    let notification: NotificationEntry
    let onSend: (String) -> Bool

    var body: some View {
        SendTextField(placeholder: "Type your follow-up...", onSend: onSend)
    }
}
