/**
 * [INPUT]: the window's effective appearance (white or black paper, D-124) and the sheet's ring and corner settings.
 * [OUTPUT]: PaperSheetView - the writing sheet: one flat tone (FirstLineColors.paperNSColor), with the sheet ring and
 *           rounded clip the room needs.
 * [POS]: The Mac half of the sheet the web paints from tokens.css; the room, its failure screen and the kept sheet
 *        all sit on this one paper. Cards, fields and controls keep FirstLineColors.sheetNSColor.
 * [PROTOCOL]: The sheet carries no texture (D-124); it repaints on size or appearance change only, never on typing.
 *             Then check FirstLine/AGENTS.md.
 */

import AppKit

@MainActor
final class PaperSheetView: NSView {
    /// The sheet's ring on the paper.
    var borderColor: NSColor? {
        didSet { needsDisplay = true }
    }
    var borderWidth: CGFloat = 0 {
        didSet { needsDisplay = true }
    }
    var cornerRadius: CGFloat = FirstLineRadius.sheet {
        didSet { updateLayerShape() }
    }
    /// Clip content (cards and the room paper) to the corner radius.
    var clipsContent: Bool = false {
        didSet { updateLayerShape() }
    }

    /// How many times the sheet has been drawn; typing and warn ticks must leave it unchanged.
    private(set) var paints = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        updateLayerShape()
        autoresizingMask = [.width, .height]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isOpaque: Bool { false }

    /// A veil that never takes a click or a key (the room's entrance curtain, D-096).
    var passesHitTests = false
    override func hitTest(_ point: NSPoint) -> NSView? { passesHitTests ? nil : super.hitTest(point) }

    private func updateLayerShape() {
        layer?.cornerRadius = cornerRadius
        layer?.masksToBounds = clipsContent
        needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        paints += 1
        let rect = bounds
        ctx.saveGState()
        if cornerRadius > 0 {
            ctx.addPath(CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil))
            ctx.clip()
        }
        effectiveAppearance.performAsCurrentDrawingAppearance { FirstLineColors.paperNSColor.setFill() }
        ctx.fill(CGRect(origin: .zero, size: rect.size))
        ctx.restoreGState()

        if let borderColor, borderWidth > 0 {
            ctx.saveGState()
            ctx.setStrokeColor(borderColor.cgColor)
            ctx.setLineWidth(borderWidth)
            ctx.addPath(CGPath(roundedRect: rect.insetBy(dx: borderWidth / 2, dy: borderWidth / 2),
                               cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil))
            ctx.strokePath()
            ctx.restoreGState()
        }
    }
}
