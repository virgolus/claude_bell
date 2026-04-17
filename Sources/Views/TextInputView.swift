import SwiftUI

struct TextInputView: View {
    let notification: NotificationEntry
    let onSend: (String) -> Void
    let onOpenTerminal: () -> Void

    var body: some View {
        SendTextField(onSend: onSend)
    }
}
