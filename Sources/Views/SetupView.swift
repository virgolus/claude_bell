import SwiftUI
import Carbon.HIToolbox

struct ShortcutRecorder: NSViewRepresentable {
    @Binding var isRecording: Bool
    let onRecord: (Int, NSEvent.ModifierFlags) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderView {
        let view = ShortcutRecorderView()
        view.onRecord = { keyCode, modifiers in
            onRecord(keyCode, modifiers)
            DispatchQueue.main.async { isRecording = false }
        }
        return view
    }

    func updateNSView(_ nsView: ShortcutRecorderView, context: Context) {
        nsView.isRecordingEnabled = isRecording
        if isRecording {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }
}

class ShortcutRecorderView: NSView {
    var onRecord: ((Int, NSEvent.ModifierFlags) -> Void)?
    var isRecordingEnabled = false

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard isRecordingEnabled else {
            super.keyDown(with: event)
            return
        }

        let flags = event.modifierFlags
        guard flags.contains(.command) || flags.contains(.control) else {
            return
        }

        let relevant: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
        onRecord?(Int(event.keyCode), flags.intersection(relevant))
    }
}
