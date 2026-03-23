import AppKit
import Quartz

private let kTrackH:  CGFloat = 42
private let kDivH:    CGFloat = 5
private let kLabelW:  CGFloat = 64
private let kHeaderH: CGFloat = 36
private let kClipPad: CGFloat = 3
private let kTabH:    CGFloat = 32

@objc(PreviewViewController)
final class PreviewViewController: NSViewController, QLPreviewingController {

    override func loadView() {
        view = TimelineView(frame: NSRect(x: 0, y: 0, width: 900, height: 500))
        preferredContentSize = CGSize(width: 900, height: 500)
    }

    func preparePreviewOfFile(at url: URL,
                               completionHandler handler: @escaping (Error?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let projects = try ProjectParser().parse(url: url)
                // Window height: based on the sequence with the most tracks
                let maxTracks = projects.map { $0.videoTracks.count + $0.audioTracks.count }.max() ?? 0
                let tabBar: Int = projects.count > 1 ? Int(kTabH) : 0
                let h = min(700, max(200,
                    tabBar + Int(kHeaderH) + maxTracks * Int(kTrackH) + Int(kDivH) + 5))
                DispatchQueue.main.async {
                    guard let self else { handler(nil); return }
                    let tv = self.view as? TimelineView
                    tv?.projects = projects
                    self.preferredContentSize = CGSize(width: 900, height: h)
                    handler(nil)
                }
            } catch {
                DispatchQueue.main.async { handler(error) }
            }
        }
    }
}

// MARK: - Timeline view

private final class TimelineView: NSView {
    var projects: [PremiereProject] = [] {
        didSet { selectedIndex = 0; needsDisplay = true }
    }
    private var selectedIndex = 0
    private var project: PremiereProject? { projects.indices.contains(selectedIndex) ? projects[selectedIndex] : nil }

    override var isFlipped: Bool { true }

    // MARK: Mouse (tab clicks)
    override func mouseDown(with event: NSEvent) {
        guard projects.count > 1 else { return }
        let pt = convert(event.locationInWindow, from: nil)
        guard pt.y < kTabH else { return }
        let tabW = bounds.width / CGFloat(projects.count)
        let idx  = Int(pt.x / tabW)
        guard idx != selectedIndex, projects.indices.contains(idx) else { return }
        selectedIndex = idx
        needsDisplay = true
    }

    // MARK: Draw
    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let b = bounds

        // Background
        fill(ctx, b, r: 0.11, g: 0.11, bl: 0.118)

        // ── Tab bar (multi-sequence) ──────────────────────────────────────────
        var contentY: CGFloat = 0
        if projects.count > 1 {
            drawTabs(ctx: ctx, width: b.width)
            contentY = kTabH
        }

        guard let p = project else { return }

        let dur = max(p.duration, 1.0)
        let pps = max(1.0, (b.width - kLabelW) / dur)

        // ── Header ────────────────────────────────────────────────────────────
        let headerRect = CGRect(x: 0, y: contentY, width: b.width, height: kHeaderH)
        fill(ctx, headerRect, r: 1, g: 1, bl: 1, a: 0.04)
        fill(ctx, CGRect(x: 0, y: contentY + kHeaderH - 0.5, width: b.width, height: 0.5),
             r: 1, g: 1, bl: 1, a: 0.09)

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor(white: 1, alpha: 0.75)
        ]
        NSAttributedString(string: p.sequenceName, attributes: titleAttrs)
            .draw(in: CGRect(x: 14, y: contentY + 9, width: b.width - 28, height: 18))

        // ── Label column ──────────────────────────────────────────────────────
        let trackAreaY = contentY + kHeaderH
        fill(ctx, CGRect(x: 0, y: trackAreaY, width: kLabelW, height: b.height - trackAreaY),
             r: 0, g: 0, bl: 0, a: 0.5)
        fill(ctx, CGRect(x: kLabelW - 0.5, y: trackAreaY, width: 0.5, height: b.height - trackAreaY),
             r: 1, g: 1, bl: 1, a: 0.07)

        // ── Tracks ────────────────────────────────────────────────────────────
        var y = trackAreaY

        func drawTracks(_ tracks: [Track]) {
            for (i, track) in tracks.enumerated() {
                if i % 2 != 0 {
                    fill(ctx, CGRect(x: 0, y: y, width: b.width, height: kTrackH),
                         r: 1, g: 1, bl: 1, a: 0.03)
                }
                fill(ctx, CGRect(x: 0, y: y + kTrackH - 0.5, width: b.width, height: 0.5),
                     r: 1, g: 1, bl: 1, a: 0.05)

                drawBadge(ctx: ctx, label: track.name, trackY: y)

                for clip in track.clips where clip.duration > 0 {
                    let cx = kLabelW + clip.startTime * pps
                    let cw = max(3, clip.duration * pps)
                    let cr = CGRect(x: cx, y: y + kClipPad, width: cw, height: kTrackH - kClipPad * 2)
                    drawClip(ctx: ctx, rect: cr, name: clip.name,
                             fillHex: clip.fillHex, strokeHex: clip.strokeHex)
                }
                y += kTrackH
            }
        }

        drawTracks(p.displayVideoTracks)

        fill(ctx, CGRect(x: 0, y: y, width: b.width, height: kDivH),
             r: 0.12, g: 0.12, bl: 0.12)
        y += kDivH

        drawTracks(p.audioTracks)
    }

    // MARK: Tab bar drawing

    private func drawTabs(ctx: CGContext, width: CGFloat) {
        let count = projects.count
        let tabW  = width / CGFloat(count)

        // Tab bar background
        fill(ctx, CGRect(x: 0, y: 0, width: width, height: kTabH), r: 0.08, g: 0.08, bl: 0.085)

        for i in 0 ..< count {
            let x = CGFloat(i) * tabW
            let isSelected = i == selectedIndex

            // Selected tab highlight
            if isSelected {
                fill(ctx, CGRect(x: x, y: 0, width: tabW, height: kTabH), r: 1, g: 1, bl: 1, a: 0.07)
                // Bottom accent line
                fill(ctx, CGRect(x: x, y: kTabH - 2, width: tabW, height: 2),
                     r: 0.25, g: 0.55, bl: 1, a: 1)
            }

            // Divider between tabs
            if i > 0 {
                fill(ctx, CGRect(x: x, y: 6, width: 0.5, height: kTabH - 12),
                     r: 1, g: 1, bl: 1, a: 0.1)
            }

            // Tab label
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: isSelected ? .semibold : .regular),
                .foregroundColor: NSColor(white: 1, alpha: isSelected ? 0.9 : 0.5)
            ]
            let str  = NSAttributedString(string: projects[i].sequenceName, attributes: attrs)
            let sz   = str.size()
            let tx   = x + (tabW - sz.width) / 2
            let ty   = (kTabH - sz.height) / 2
            str.draw(at: CGPoint(x: tx, y: ty))
        }

        // Bottom border
        fill(ctx, CGRect(x: 0, y: kTabH - 0.5, width: width, height: 0.5),
             r: 1, g: 1, bl: 1, a: 0.07)
    }

    // MARK: Helpers

    private func fill(_ ctx: CGContext, _ rect: CGRect,
                      r: CGFloat, g: CGFloat, bl: CGFloat, a: CGFloat = 1) {
        ctx.setFillColor(CGColor(srgbRed: r, green: g, blue: bl, alpha: a))
        ctx.fill(rect)
    }

    private func drawBadge(ctx: CGContext, label: String, trackY: CGFloat) {
        let bh: CGFloat = 20
        let bw = kLabelW - 16
        let bx: CGFloat = 8
        let by = trackY + (kTrackH - bh) / 2
        let path = CGPath(roundedRect: CGRect(x: bx, y: by, width: bw, height: bh),
                          cornerWidth: 5, cornerHeight: 5, transform: nil)
        ctx.setFillColor(CGColor(srgbRed: 0.2, green: 0.44, blue: 0.85, alpha: 0.9))
        ctx.addPath(path); ctx.fillPath()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        let str = NSAttributedString(string: label, attributes: attrs)
        let sz  = str.size()
        str.draw(at: CGPoint(x: bx + (bw - sz.width) / 2, y: by + (bh - sz.height) / 2))
    }

    private func drawClip(ctx: CGContext, rect: CGRect,
                          name: String, fillHex: String, strokeHex: String) {
        let path = CGPath(roundedRect: rect, cornerWidth: 3, cornerHeight: 3, transform: nil)

        if let c = cgColor(hex: fillHex) {
            ctx.setFillColor(c); ctx.addPath(path); ctx.fillPath()
        }
        if let c = cgColor(hex: strokeHex), rect.width >= 4 {
            ctx.setStrokeColor(c); ctx.setLineWidth(1.5)
            ctx.addPath(path); ctx.strokePath()
        }
        if rect.width >= 20 {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.white
            ]
            NSAttributedString(string: name, attributes: attrs).draw(
                with: CGRect(x: rect.minX + 5, y: rect.minY + 3,
                             width: rect.width - 10, height: rect.height - 6),
                options: [.truncatesLastVisibleLine, .usesLineFragmentOrigin])
        }
    }
}

// MARK: - Hex → CGColor

private func cgColor(hex: String) -> CGColor? {
    let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
    guard s.count == 6 else { return nil }
    var v: UInt64 = 0
    guard Scanner(string: s).scanHexInt64(&v) else { return nil }
    return CGColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                  green:    CGFloat((v >>  8) & 0xFF) / 255,
                  blue:     CGFloat( v        & 0xFF) / 255,
                  alpha: 1)
}
