import AppKit
import CoreText

/// The bubble's own window: borderless, transparent, and as incapable of taking
/// focus as the pet itself. It also never takes mouse events — it is an
/// information card, not a control. (Selectable bubble text would need a focus
/// design of its own; see `docs/MACOS-CONSTRAINTS.md` §1.)
final class BubbleWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override var acceptsFirstResponder: Bool { false }
}

/// Draws the bubble: card, tail, wrapped text.
///
/// Text goes through Core Text rather than AppKit string drawing so the exact
/// same code path renders in a window and in the headless `--render-png` sheet
/// and can be measured in `--selftest`. "It looked right on screen" is not
/// evidence, and the pose sheet is how the artwork gets reviewed.
enum BubbleRenderer {
    static let padding: CGFloat = 11
    static let tailHeight: CGFloat = 7
    static let tailHalfWidth: CGFloat = 8
    static let cornerRadius: CGFloat = 11
    static let maxTextWidth: CGFloat = 230
    static let fontSize: CGFloat = 12.5

    // MARK: - Palette

    static func textColor(for style: BubbleStyle) -> CGColor {
        style == .code ? CGColor.hex(0xEDEFF5) : CGColor.hex(0x3A2E27)
    }

    static func background(for style: BubbleStyle) -> CGColor {
        switch style {
        case .plain: return CGColor.hex(0xFDFCFA)
        case .info: return CGColor.hex(0xF2F6FF)
        case .warning: return CGColor.hex(0xFFF7E9)
        case .success: return CGColor.hex(0xF0FAEF)
        case .code: return CGColor.hex(0x2B2F3A)
        }
    }

    static func border(for style: BubbleStyle) -> CGColor {
        switch style {
        case .plain: return CGColor.hex(0xD8C9B6)
        case .info: return CGColor.hex(0xB6C8E6)
        case .warning: return CGColor.hex(0xE6C089)
        case .success: return CGColor.hex(0xA3D19C)
        case .code: return CGColor.hex(0x1B1E26)
        }
    }

    static func font(for style: BubbleStyle) -> CTFont {
        let name = style == .code ? "Menlo-Regular" : ".AppleSystemUIFont"
        return CTFontCreateWithName(name as CFString, fontSize, nil)
    }

    // MARK: - Layout

    static func attributed(_ content: BubbleContent) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        return NSAttributedString(
            string: content.text,
            attributes: [
                .font: font(for: content.style),
                .foregroundColor: textColor(for: content.style),
                .paragraphStyle: paragraph,
            ]
        )
    }

    static func textSize(for content: BubbleContent) -> CGSize {
        let string = attributed(content)
        let framesetter = CTFramesetterCreateWithAttributedString(string)
        var fitRange = CFRange()
        let suggested = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: 0),
            nil,
            CGSize(width: maxTextWidth, height: .greatestFiniteMagnitude),
            &fitRange
        )
        return CGSize(width: ceil(suggested.width), height: ceil(suggested.height))
    }

    /// Window size for this content, tail included.
    static func windowSize(for content: BubbleContent) -> CGSize {
        let text = textSize(for: content)
        return CGSize(
            width: text.width + padding * 2,
            height: text.height + padding * 2 + tailHeight
        )
    }

    /// Where the text goes, in the same space as `draw`.
    static func textRect(in size: CGSize, tailOnBottom: Bool) -> CGRect {
        CGRect(
            x: padding,
            y: (tailOnBottom ? tailHeight : 0) + padding,
            width: size.width - padding * 2,
            height: size.height - tailHeight - padding * 2
        )
    }

    // MARK: - Drawing

    /// Draw into `context`, whose origin is the bubble window's bottom-left.
    /// `tailX` is where the tail points at the cat, in the same space;
    /// `tailOnBottom` is true when the bubble sits above the cat.
    static func draw(
        in context: CGContext,
        size: CGSize,
        content: BubbleContent,
        tailX: CGFloat,
        tailOnBottom: Bool
    ) {
        let bubbleRect = CGRect(
            x: 0,
            y: tailOnBottom ? tailHeight : 0,
            width: size.width,
            height: size.height - tailHeight
        )

        let card = CGPath(
            roundedRect: bubbleRect,
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )
        let clampedTailX = min(
            max(tailX, cornerRadius + tailHalfWidth),
            max(cornerRadius + tailHalfWidth, size.width - cornerRadius - tailHalfWidth)
        )
        let tail = tailPath(bubbleRect: bubbleRect, tailX: clampedTailX, pointsDown: tailOnBottom)
        let tailOutline = tailSides(bubbleRect: bubbleRect, tailX: clampedTailX, pointsDown: tailOnBottom)

        context.saveGState()
        defer { context.restoreGState() }
        context.setShouldAntialias(true)

        context.addPath(card)
        context.addPath(tail)
        context.setFillColor(background(for: content.style))
        context.fillPath()

        context.addPath(card)
        context.setStrokeColor(border(for: content.style))
        context.setLineWidth(1)
        context.strokePath()

        // Refill the tail to erase the card's border where the two overlap, then
        // stroke only its two slanted sides: no hairline across the pointer.
        context.addPath(tail)
        context.setFillColor(background(for: content.style))
        context.fillPath()

        context.addPath(tailOutline)
        context.setStrokeColor(border(for: content.style))
        context.setLineWidth(1)
        context.strokePath()

        drawText(in: context, size: size, content: content, tailOnBottom: tailOnBottom)
    }

    /// Core Text lays lines out downward from the top of the path rect, which is
    /// exactly what an unflipped CG context needs.
    private static func drawText(
        in context: CGContext,
        size: CGSize,
        content: BubbleContent,
        tailOnBottom: Bool
    ) {
        let rect = textRect(in: size, tailOnBottom: tailOnBottom)
        guard rect.width > 1, rect.height > 1 else { return }

        let framesetter = CTFramesetterCreateWithAttributedString(attributed(content))
        let path = CGPath(rect: rect, transform: nil)
        let frame = CTFramesetterCreateFrame(
            framesetter,
            CFRange(location: 0, length: 0),
            path,
            nil
        )

        context.saveGState()
        defer { context.restoreGState() }
        context.textMatrix = .identity
        CTFrameDraw(frame, context)
    }

    /// The little pointer. Merged with the card by filling both paths, so no
    /// seam shows where they meet.
    static func tailPath(bubbleRect: CGRect, tailX: CGFloat, pointsDown: Bool) -> CGPath {
        let path = CGMutablePath()
        if pointsDown {
            path.move(to: CGPoint(x: tailX - tailHalfWidth, y: bubbleRect.minY + 1))
            path.addLine(to: CGPoint(x: tailX, y: bubbleRect.minY - tailHeight))
            path.addLine(to: CGPoint(x: tailX + tailHalfWidth, y: bubbleRect.minY + 1))
        } else {
            path.move(to: CGPoint(x: tailX - tailHalfWidth, y: bubbleRect.maxY - 1))
            path.addLine(to: CGPoint(x: tailX, y: bubbleRect.maxY + tailHeight))
            path.addLine(to: CGPoint(x: tailX + tailHalfWidth, y: bubbleRect.maxY - 1))
        }
        path.closeSubpath()
        return path
    }

    /// Just the two slanted sides, so the base is not stroked over the card.
    static func tailSides(bubbleRect: CGRect, tailX: CGFloat, pointsDown: Bool) -> CGPath {
        let path = CGMutablePath()
        if pointsDown {
            path.move(to: CGPoint(x: tailX - tailHalfWidth, y: bubbleRect.minY + 1))
            path.addLine(to: CGPoint(x: tailX, y: bubbleRect.minY - tailHeight))
            path.addLine(to: CGPoint(x: tailX + tailHalfWidth, y: bubbleRect.minY + 1))
        } else {
            path.move(to: CGPoint(x: tailX - tailHalfWidth, y: bubbleRect.maxY - 1))
            path.addLine(to: CGPoint(x: tailX, y: bubbleRect.maxY + tailHeight))
            path.addLine(to: CGPoint(x: tailX + tailHalfWidth, y: bubbleRect.maxY - 1))
        }
        return path
    }
}

/// Hosts the bubble drawing. Text layout is cached per revision so following the
/// cat around the screen does not re-shape the string every frame.
final class BubbleView: NSView {
    private var content: BubbleContent?
    private var tailX: CGFloat = 0
    private var tailOnBottom = true
    private var cachedRevision = -1

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { false }

    func update(content: BubbleContent?, revision: Int) {
        guard revision != cachedRevision else { return }
        cachedRevision = revision
        self.content = content
        needsDisplay = true
    }

    func setTail(x: CGFloat, onBottom: Bool) {
        guard abs(x - tailX) > 0.5 || onBottom != tailOnBottom else { return }
        tailX = x
        tailOnBottom = onBottom
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext, let content else { return }
        context.clear(bounds)
        BubbleRenderer.draw(
            in: context,
            size: bounds.size,
            content: content,
            tailX: tailX,
            tailOnBottom: tailOnBottom
        )
    }
}
