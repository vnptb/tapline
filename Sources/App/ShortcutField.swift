import SwiftUI
import Carbon.HIToolbox

/// Click, then press a key combination to record it.
struct ShortcutField: NSViewRepresentable {
    @Binding var keyCode: UInt16?
    @Binding var flags: CGEventFlags

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView()
        view.onRecord = { code, flags in
            keyCode = code
            self.flags = flags
        }
        return view
    }

    func updateNSView(_ view: RecorderView, context: Context) {
        view.shortcut = keyCode.map { KeyNames.shortcut(keyCode: $0, flags: flags) }
    }

    final class RecorderView: NSView {
        var onRecord: ((UInt16, CGEventFlags) -> Void)?
        var shortcut: String? { didSet { needsDisplay = true } }
        private var recording = false { didSet { needsDisplay = true } }

        override var acceptsFirstResponder: Bool { true }
        override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 28) }

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            recording = true
        }

        override func resignFirstResponder() -> Bool {
            recording = false
            return true
        }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard recording else { return false }
            keyDown(with: event)
            return true
        }

        override func keyDown(with event: NSEvent) {
            guard recording else { return super.keyDown(with: event) }
            if Int(event.keyCode) == kVK_Escape && event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
                recording = false
                return
            }
            onRecord?(event.keyCode, KeyNames.flags(from: event.modifierFlags))
            recording = false
        }

        override func draw(_ dirtyRect: NSRect) {
            let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
            let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
            (recording ? NSColor.controlAccentColor.withAlphaComponent(0.08) : NSColor.textBackgroundColor).setFill()
            path.fill()
            (recording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
            path.lineWidth = recording ? 2 : 1
            path.stroke()

            let text = recording ? L("Press a shortcut…") : (shortcut ?? L("Click to record"))
            let color: NSColor = (recording || shortcut == nil) ? .secondaryLabelColor : .labelColor
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13, weight: shortcut != nil && !recording ? .semibold : .regular),
                .foregroundColor: color,
            ]
            let size = (text as NSString).size(withAttributes: attrs)
            (text as NSString).draw(at: NSPoint(x: 10, y: (bounds.height - size.height) / 2), withAttributes: attrs)
        }
    }
}
