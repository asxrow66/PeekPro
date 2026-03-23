import Foundation

enum HTMLGenerator {

    private static let trackH   = 42
    private static let dividerH = 5
    private static let labelW   = 64
    private static let clipPad  = 3

    static func generate(from project: PremiereProject) -> String {
        let dur  = max(project.duration, 1.0)
        let pps  = max(5.0, min(80.0, 2400.0 / dur))
        let cW   = max(900, Int(dur * pps) + 80)

        var labelHTML = ""; var contentHTML = ""

        for (i, track) in project.displayVideoTracks.enumerated() {
            labelHTML   += labelRow(track.name)
            contentHTML += trackRow(track, index: i, pps: pps)
        }
        let div = "<div style=\"height:\(dividerH)px;background:#1e1e1e;\"></div>\n"
        labelHTML += div; contentHTML += div

        for (i, track) in project.audioTracks.enumerated() {
            labelHTML   += labelRow(track.name)
            contentHTML += trackRow(track, index: i, pps: pps)
        }
        return page(title: esc(project.sequenceName),
                    labelHTML: labelHTML, contentHTML: contentHTML, contentW: cW)
    }

    private static func labelRow(_ name: String) -> String {
        "<div style=\"height:\(trackH)px;display:flex;align-items:center;" +
        "justify-content:center;\">" +
        "<div style=\"background:rgba(51,112,217,0.9);color:#fff;font-size:12px;" +
        "font-weight:700;padding:3px 8px;border-radius:5px;\">\(esc(name))</div></div>\n"
    }

    private static func trackRow(_ track: Track, index: Int, pps: Double) -> String {
        let bg = index % 2 == 0 ? "transparent" : "rgba(255,255,255,0.03)"
        var clips = ""
        for clip in track.clips where clip.duration > 0 {
            let x = Int(clip.startTime * pps)
            let w = max(4, Int(clip.duration * pps))
            let text = w >= 20
                ? "<span style=\"font-size:11px;font-weight:500;color:#fff;" +
                  "overflow:hidden;text-overflow:ellipsis;white-space:nowrap;\">\(esc(clip.name))</span>"
                : ""
            clips +=
                "<div style=\"position:absolute;top:\(clipPad)px;bottom:\(clipPad)px;" +
                "left:\(x)px;width:\(w)px;background:\(clip.label.hex);border-radius:3px;" +
                "box-shadow:inset 0 0 0 1.5px \(clip.label.strokeHex);" +
                "display:flex;align-items:center;padding:0 5px;overflow:hidden;\">\(text)</div>\n"
        }
        return "<div style=\"height:\(trackH)px;position:relative;background:\(bg);" +
               "border-bottom:1px solid rgba(255,255,255,0.05);\">\(clips)</div>\n"
    }

    private static func page(title: String, labelHTML: String,
                               contentHTML: String, contentW: Int) -> String {
        """
        <!DOCTYPE html><html><head><meta charset="UTF-8">
        <meta name="color-scheme" content="dark">
        <style>
        *{box-sizing:border-box;margin:0;padding:0}
        html,body{height:100%;overflow:hidden;background:#1c1c1e;color:#fff;
          font-family:-apple-system,BlinkMacSystemFont,sans-serif}
        .hdr{padding:9px 14px;font-size:13px;font-weight:600;
          color:rgba(255,255,255,.75);border-bottom:1px solid rgba(255,255,255,.09);
          background:rgba(255,255,255,.04);flex-shrink:0;
          white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
        .wrap{display:flex;height:calc(100% - 36px);overflow:hidden}
        .labels{width:\(labelW)px;flex-shrink:0;background:rgba(0,0,0,.5);
          border-right:1px solid rgba(255,255,255,.07)}
        .scroll{flex:1;overflow-x:auto;overflow-y:hidden}
        .scroll::-webkit-scrollbar{height:7px}
        .scroll::-webkit-scrollbar-track{background:rgba(255,255,255,.04)}
        .scroll::-webkit-scrollbar-thumb{background:rgba(255,255,255,.22);border-radius:4px}
        .inner{min-width:100%;height:100%}
        </style></head><body>
        <div class="hdr">\(title)</div>
        <div class="wrap">
          <div class="labels">\(labelHTML)</div>
          <div class="scroll"><div class="inner" style="width:\(contentW)px">\(contentHTML)</div></div>
        </div></body></html>
        """
    }

    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
