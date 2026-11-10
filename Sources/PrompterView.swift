import AppKit

/// Draws the script inside the notch panel and drives scrolling, either at a
/// steady speed or by following the speaker's position in the script.
final class PrompterView: NSView {
    private let model: PrompterModel
    private let storage = NSTextStorage()
    private let layoutManager = NSLayoutManager()
    private let container = NSTextContainer(size: .zero)
    private let hPad: CGFloat = 22

    /// Normalized script words with their character ranges, for voice following.
    private var words: [(word: String, range: NSRange)] = []
    private var cursor = 0

    private var offset: CGFloat = 0
    private var voiceTarget: CGFloat?
    private var lastTick: CFTimeInterval = 0
    private var link: CADisplayLink?
    private var builtWidth: CGFloat = -1
    private var drawnState: (paused: Bool, mode: ScrollMode)?

    var notchHeight: CGFloat = 0 { didSet { needsDisplay = true } }
    var onEscape: (() -> Void)?

    init(model: PrompterModel) {
        self.model = model
        super.init(frame: .zero)
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)
        container.lineFragmentPadding = 0
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil, link == nil {
            let l = displayLink(target: self, selector: #selector(step(_:)))
            l.add(to: .main, forMode: .common)
            link = l
        } else if window == nil {
            link?.invalidate()
            link = nil
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if newSize.width != builtWidth { rebuild() }
    }

    // MARK: Geometry

    private var textAreaTop: CGFloat { notchHeight + 8 }
    private var textAreaHeight: CGFloat { max(20, bounds.height - textAreaTop - 10) }
    /// Where the line being spoken sits in voice mode, measured from the top of the text area.
    private var readingLine: CGFloat { textAreaHeight * 0.25 }
    private var contentHeight: CGFloat { layoutManager.usedRect(for: container).height }
    private var minOffset: CGFloat { -readingLine }
    private var maxOffset: CGFloat { max(0, contentHeight - CGFloat(model.fontSize)) }

    private func clampOffset() {
        offset = min(max(offset, minOffset), maxOffset)
    }

    // MARK: Text

    func rebuild() {
        builtWidth = bounds.width
        let size = CGFloat(model.fontSize)
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.lineSpacing = size * 0.22
        para.paragraphSpacing = size * 0.6
        storage.setAttributedString(NSAttributedString(string: model.script, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: .semibold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: para,
        ]))
        container.size = NSSize(width: max(60, bounds.width - hPad * 2), height: .greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: container)
        indexWords()
        cursor = min(cursor, words.count)
        if model.mode == .voice { setCursor(cursor) }
        clampOffset()
        needsDisplay = true
    }

    private func indexWords() {
        words = []
        let ns = model.script as NSString
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byWords) { sub, range, _, _ in
            guard let sub else { return }
            let w = Self.normalize(sub)
            if !w.isEmpty { self.words.append((w, range)) }
        }
    }

    static func normalize(_ s: String) -> String {
        s.lowercased().folding(options: .diacriticInsensitive, locale: nil).filter { $0.isLetter || $0.isNumber }
    }

    // MARK: Playback

    func restart() {
        offset = model.mode == .voice ? minOffset : 0
        voiceTarget = nil
        setCursor(0)
        needsDisplay = true
    }

    func modeChanged() {
        if model.mode == .voice {
            setCursor(wordIndexAtReadingLine())
        } else {
            voiceTarget = nil
            dimSpoken(upTo: 0)
        }
        needsDisplay = true
    }

    @objc private func step(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        let dt = lastTick == 0 ? 0 : min(now - lastTick, 0.1)
        lastTick = now

        let before = offset
        if model.mode == .voice {
            if let t = voiceTarget, !model.isPaused, abs(t - offset) > 0.3 {
                offset += (t - offset) * CGFloat(min(1, dt * 5))
            }
        } else if !model.isPaused, storage.length > 0 {
            offset += CGFloat(model.speed * dt)
            if offset >= maxOffset {
                offset = maxOffset
                model.isPaused = true
            }
        }
        let state = (model.isPaused, model.mode)
        if offset != before || drawnState == nil || drawnState! != state {
            needsDisplay = true
        }
    }

    // MARK: Voice following

    /// Advances the cursor to the end of the last few spoken words when they
    /// match the script just ahead of the current position.
    func follow(spoken: [String]) {
        guard model.mode == .voice, !model.isPaused, !words.isEmpty else { return }
        let tail = spoken.suffix(4).map(Self.normalize).filter { !$0.isEmpty }
        guard !tail.isEmpty else { return }
        let lo = max(0, cursor - 2)
        for n in stride(from: min(3, tail.count), through: 1, by: -1) {
            let seq = Array(tail.suffix(n))
            // A single word only counts when it is distinctive and close by.
            if n == 1 && seq[0].count < 4 { continue }
            let hi = min(words.count, cursor + (n == 1 ? 5 : 30))
            guard hi - lo >= n else { continue }
            for i in lo...(hi - n) where (0..<n).allSatisfy({ Self.similar(words[i + $0].word, seq[$0]) }) {
                if i + n > cursor { setCursor(i + n) }
                return
            }
        }
    }

    private func setCursor(_ index: Int) {
        cursor = max(0, min(index, words.count))
        dimSpoken(upTo: cursor)
        guard model.mode == .voice else { return }
        guard !words.isEmpty else { voiceTarget = minOffset; return }
        let range = words[min(cursor, words.count - 1)].range
        let glyph = layoutManager.glyphIndexForCharacter(at: range.location)
        let line = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        voiceTarget = min(max(line.minY - readingLine, minOffset), maxOffset)
    }

    private func dimSpoken(upTo index: Int) {
        guard storage.length > 0 else { return }
        let split = index >= words.count ? storage.length : (index == 0 ? 0 : words[index].range.location)
        storage.beginEditing()
        storage.addAttribute(.foregroundColor, value: NSColor.white, range: NSRange(location: 0, length: storage.length))
        if split > 0 {
            storage.addAttribute(.foregroundColor, value: NSColor.white.withAlphaComponent(0.4), range: NSRange(location: 0, length: split))
        }
        storage.endEditing()
        needsDisplay = true
    }

    private func wordIndexAtReadingLine() -> Int {
        guard storage.length > 0 else { return 0 }
        let point = NSPoint(x: container.size.width / 2, y: max(0, offset + readingLine))
        let glyph = layoutManager.glyphIndex(for: point, in: container)
        let lineGlyphs = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let firstGlyph = layoutManager.glyphIndex(for: NSPoint(x: 0, y: lineGlyphs.midY), in: container)
        let char = layoutManager.characterIndexForGlyph(at: firstGlyph)
        return words.firstIndex { $0.range.location >= char } ?? words.count
    }

    private static func similar(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        let shorter = min(a.count, b.count)
        if shorter >= 4 && (a.hasPrefix(b) || b.hasPrefix(a)) { return true }
        return shorter >= 5 && editDistance(a, b) <= 1
    }

    private static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        var prev = Array(0...b.count)
        for i in 1...max(1, a.count) where !a.isEmpty {
            var cur = [i] + Array(repeating: 0, count: b.count)
            for j in 1...max(1, b.count) where !b.isEmpty {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            prev = cur
        }
        return prev[b.count]
    }

    // MARK: Input

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        window?.makeFirstResponder(self)
    }

    override func scrollWheel(with event: NSEvent) {
        let factor: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 12
        offset -= event.scrollingDeltaY * factor
        clampOffset()
        if model.mode == .voice {
            voiceTarget = offset
            cursor = wordIndexAtReadingLine()
            dimSpoken(upTo: cursor)
        }
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 49: model.isPaused.toggle()                       // space
        case 126: model.speed = min(200, model.speed + 5)      // up
        case 125: model.speed = max(5, model.speed - 5)        // down
        case 15: restart()                                     // R
        case 53: onEscape?()                                   // esc
        default: super.keyDown(with: event)
        }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        drawnState = (model.isPaused, model.mode)
        let r = bounds
        NSColor.black.setFill()
        bottomRoundedPath(r, radius: 20).fill()

        let textRect = NSRect(x: 0, y: textAreaTop, width: r.width, height: textAreaHeight)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: textRect).addClip()
        let visible = NSRect(x: 0, y: offset, width: container.size.width, height: textAreaHeight)
        let glyphs = layoutManager.glyphRange(forBoundingRect: visible, in: container)
        layoutManager.drawGlyphs(forGlyphRange: glyphs, at: NSPoint(x: hPad, y: textAreaTop - offset))
        NSGraphicsContext.restoreGraphicsState()

        // Fade the text in and out at the edges of the text area.
        let fade = min(22, textAreaHeight * 0.22)
        let clear = NSColor.black.withAlphaComponent(0)
        NSGradient(starting: .black, ending: clear)?.draw(in: NSRect(x: 0, y: textAreaTop, width: r.width, height: fade), angle: 90)
        NSGradient(starting: .black, ending: clear)?.draw(in: NSRect(x: 0, y: textRect.maxY - fade, width: r.width, height: fade), angle: 270)

        if model.mode == .voice {
            // Marker for the reading line.
            let y = textAreaTop + readingLine + CGFloat(model.fontSize) * 0.6
            NSColor.systemGreen.withAlphaComponent(model.isPaused ? 0.3 : 0.9).setFill()
            NSBezierPath(ovalIn: NSRect(x: 8, y: y - 3, width: 6, height: 6)).fill()
        }
        if model.isPaused {
            NSColor.white.withAlphaComponent(0.5).setFill()
            let x = r.maxX - 24, y = r.maxY - 22
            NSBezierPath(roundedRect: NSRect(x: x, y: y, width: 4, height: 12), xRadius: 1, yRadius: 1).fill()
            NSBezierPath(roundedRect: NSRect(x: x + 7, y: y, width: 4, height: 12), xRadius: 1, yRadius: 1).fill()
        }
    }

    private func bottomRoundedPath(_ r: NSRect, radius: CGFloat) -> NSBezierPath {
        // Flipped view: maxY is the visual bottom.
        let p = NSBezierPath()
        p.move(to: NSPoint(x: r.minX, y: r.minY))
        p.line(to: NSPoint(x: r.maxX, y: r.minY))
        p.line(to: NSPoint(x: r.maxX, y: r.maxY - radius))
        p.curve(to: NSPoint(x: r.maxX - radius, y: r.maxY),
                controlPoint1: NSPoint(x: r.maxX, y: r.maxY), controlPoint2: NSPoint(x: r.maxX, y: r.maxY))
        p.line(to: NSPoint(x: r.minX + radius, y: r.maxY))
        p.curve(to: NSPoint(x: r.minX, y: r.maxY - radius),
                controlPoint1: NSPoint(x: r.minX, y: r.maxY), controlPoint2: NSPoint(x: r.minX, y: r.maxY))
        p.close()
        return p
    }
}
