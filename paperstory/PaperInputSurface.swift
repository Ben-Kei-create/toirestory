import SwiftUI
import AppKit

/// A transparent AppKit input layer keeps mouse and trackpad input separate from the Metal view.
struct PaperInputSurface: NSViewRepresentable {
    let onChanged: (CGPoint, CGSize) -> Void
    let onEnded: (CGPoint, CGSize, CGSize) -> Void
    let onScroll: (CGFloat) -> Void

    func makeNSView(context: Context) -> PaperInputView {
        let view = PaperInputView()
        updateNSView(view, context: context)
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.group)
        view.setAccessibilityLabel("巻紙。下へドラッグ、スクロール、または下矢印キーで読み進めます。")
        return view
    }

    func updateNSView(_ view: PaperInputView, context: Context) {
        view.onChanged = onChanged
        view.onEnded = onEnded
        view.onScroll = onScroll
    }
}

final class PaperInputView: NSView {
    var onChanged: ((CGPoint, CGSize) -> Void)?
    var onEnded: ((CGPoint, CGSize, CGSize) -> Void)?
    var onScroll: ((CGFloat) -> Void)?
    private var start: CGPoint?
    private var lastPoint: CGPoint = .zero
    private var lastTime: TimeInterval = 0
    private var velocity: CGSize = .zero

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        start = point
        lastPoint = point
        lastTime = event.timestamp
        velocity = .zero
        NSCursor.closedHand.set()
        onChanged?(point, .zero)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        let point = convert(event.locationInWindow, from: nil)
        let dt = event.timestamp - lastTime
        if dt > 0 {
            velocity = CGSize(width: (point.x - lastPoint.x) / dt, height: (point.y - lastPoint.y) / dt)
        }
        lastPoint = point
        lastTime = event.timestamp
        onChanged?(start, CGSize(width: point.x - start.x, height: point.y - start.y))
    }

    override func mouseUp(with event: NSEvent) {
        guard let start else { return }
        let point = convert(event.locationInWindow, from: nil)
        let translation = CGSize(width: point.x - start.x, height: point.y - start.y)
        if point != lastPoint { onChanged?(start, translation) }
        let releaseVelocity = event.timestamp - lastTime < 0.12 ? velocity : .zero
        onEnded?(start, translation, releaseVelocity)
        self.start = nil
        NSCursor.openHand.set()
    }

    override func scrollWheel(with event: NSEvent) {
        onScroll?(-event.scrollingDeltaY)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 125: onScroll?(28)
        case 126: onScroll?(-28)
        default: super.keyDown(with: event)
        }
    }
}
