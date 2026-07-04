import Foundation

// MARK: - Premiere label colours (hex only — no AppKit dependency needed)

enum PremiereLabel: String {
    case none      = "No Label"
    case violet    = "Violet"
    case iris      = "Iris"
    case caribbean = "Caribbean"
    case lavender  = "Lavender"
    case cerulean  = "Cerulean"
    case forest    = "Forest"
    case rose      = "Rose"
    case mango     = "Mango"
    case purple    = "Purple"
    case blue      = "Blue"
    case teal      = "Teal"
    case magenta   = "Magenta"
    case tan       = "Tan"
    case green     = "Green"
    case brown     = "Brown"
    case yellow    = "Yellow"

    /// Fill colour hex — Premiere Pro default label colours, decoded from the
    /// BGR ints Premiere stores in prefs as BE.Prefs.LabelColors.0–15
    var hex: String {
        switch self {
        case .none:      return "#72727a"
        case .violet:    return "#3e0aae"
        case .iris:      return "#004b67"
        case .caribbean: return "#2a5507"
        case .lavender:  return "#751187"
        case .cerulean:  return "#05555b"
        case .forest:    return "#3d4a00"
        case .rose:      return "#8c0235"
        case .mango:     return "#893a04"
        case .purple:    return "#6100b7"
        case .blue:      return "#122d9a"
        case .teal:      return "#014e45"
        case .magenta:   return "#840d58"
        case .tan:       return "#6f5a45"
        case .green:     return "#0d5d27"
        case .brown:     return "#5d3b06"
        case .yellow:    return "#6f6619"
        }
    }

    /// Inner-stroke colour (~30 % lighter than fill so clip edges stay visible
    /// against the dark fills)
    var strokeHex: String {
        guard hex.count == 7, let v = Int(hex.dropFirst(), radix: 16) else { return hex }
        let scale: (Int) -> Int = { min(Int(Double($0) * 1.3) + 12, 255) }
        let r = scale((v >> 16) & 0xFF)
        let g = scale((v >>  8) & 0xFF)
        let b = scale( v        & 0xFF)
        return String(format: "#%02x%02x%02x", r, g, b)
    }

    /// Maps BE.Prefs.LabelColors.N slot index (0–15) to a label
    static func from(id: Int) -> PremiereLabel {
        switch id {
        case 0:  return .violet
        case 1:  return .iris
        case 2:  return .caribbean
        case 3:  return .lavender
        case 4:  return .cerulean
        case 5:  return .forest
        case 6:  return .rose
        case 7:  return .mango
        case 8:  return .purple
        case 9:  return .blue
        case 10: return .teal
        case 11: return .magenta
        case 12: return .tan
        case 13: return .green
        case 14: return .brown
        case 15: return .yellow
        default: return .none
        }
    }

    static func from(name: String) -> PremiereLabel {
        switch name.lowercased().trimmingCharacters(in: .whitespaces) {
        case "violet":    return .violet
        case "iris":      return .iris
        case "caribbean": return .caribbean
        case "lavender":  return .lavender
        case "cerulean":  return .cerulean
        case "forest":    return .forest
        case "rose":      return .rose
        case "mango":     return .mango
        case "purple":    return .purple
        case "blue":      return .blue
        case "teal":      return .teal
        case "magenta":   return .magenta
        case "tan":       return .tan
        case "green":     return .green
        case "brown":     return .brown
        case "yellow":    return .yellow
        default:          return .none
        }
    }
}

// MARK: - Data models

enum TrackType { case video, audio }

struct Clip {
    var name: String
    var startTime: Double
    var endTime: Double
    var label: PremiereLabel
    var duration: Double { max(endTime - startTime, 0) }
}

struct Track {
    var name: String
    var trackType: TrackType
    var clips: [Clip]
}

struct PremiereProject {
    var sequenceName: String
    var videoTracks: [Track]
    var audioTracks: [Track]
    var duration: Double
    var fps: Double
    var displayVideoTracks: [Track] { videoTracks.reversed() }
}
