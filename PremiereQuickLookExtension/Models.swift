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

    /// Fill colour hex (matches Premiere Pro default label colours, slots 1–16)
    var hex: String {
        switch self {
        case .none:      return "#72727a"
        case .violet:    return "#8040ff"
        case .iris:      return "#00e4ff"
        case .caribbean: return "#3ea672"
        case .lavender:  return "#cc66ff"
        case .cerulean:  return "#0087be"
        case .forest:    return "#669900"
        case .rose:      return "#cc0066"
        case .mango:     return "#e06a00"
        case .purple:    return "#9900cc"
        case .blue:      return "#0000ff"
        case .teal:      return "#009999"
        case .magenta:   return "#ff00ff"
        case .tan:       return "#998266"
        case .green:     return "#009900"
        case .brown:     return "#996600"
        case .yellow:    return "#999900"
        }
    }

    /// Inner-stroke colour (~35 % darker than fill)
    var strokeHex: String {
        switch self {
        case .none:      return "#4a4a4f"
        case .violet:    return "#5329a5"
        case .iris:      return "#0093a5"
        case .caribbean: return "#286b4a"
        case .lavender:  return "#8442a5"
        case .cerulean:  return "#00577b"
        case .forest:    return "#426300"
        case .rose:      return "#840042"
        case .mango:     return "#914500"
        case .purple:    return "#630084"
        case .blue:      return "#0000a5"
        case .teal:      return "#006363"
        case .magenta:   return "#a500a5"
        case .tan:       return "#635442"
        case .green:     return "#006300"
        case .brown:     return "#634200"
        case .yellow:    return "#636300"
        }
    }

    /// Maps BE.Prefs.LabelColors.N slot index (1–16) to a label
    static func from(id: Int) -> PremiereLabel {
        switch id {
        case 1:  return .violet
        case 2:  return .iris
        case 3:  return .caribbean
        case 4:  return .lavender
        case 5:  return .cerulean
        case 6:  return .forest
        case 7:  return .rose
        case 8:  return .mango
        case 9:  return .purple
        case 10: return .blue
        case 11: return .teal
        case 12: return .magenta
        case 13: return .tan
        case 14: return .green
        case 15: return .brown
        case 16: return .yellow
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
    var colorInt: Int = -1       // asl.clip.label.color; stored as BGR integer (-1 = use label fallback)
    var duration: Double { max(endTime - startTime, 0) }

    /// Fill hex — decoded from BGR colorInt when available, else label default
    var fillHex: String {
        guard colorInt > 0 else { return label.hex }
        let b = (colorInt >> 16) & 0xFF
        let g = (colorInt >>  8) & 0xFF
        let r =  colorInt        & 0xFF
        return String(format: "#%02x%02x%02x", r, g, b)
    }

    /// Stroke hex — 35% darker than fill
    var strokeHex: String {
        guard colorInt > 0 else { return label.strokeHex }
        let b = Int(Double((colorInt >> 16) & 0xFF) * 0.65)
        let g = Int(Double((colorInt >>  8) & 0xFF) * 0.65)
        let r = Int(Double( colorInt        & 0xFF) * 0.65)
        return String(format: "#%02x%02x%02x", r, g, b)
    }
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
