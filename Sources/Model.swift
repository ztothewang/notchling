import AppKit
import Observation

enum ScrollMode: String, CaseIterable {
    case steady, voice
}

enum AppAppearance: String, CaseIterable {
    case system, light, dark

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

enum ModelChange {
    case script, layout, mode
}

@MainActor @Observable
final class PrompterModel {
    private static let defaults = UserDefaults.standard

    var script: String { didSet { Self.defaults.set(script, forKey: "script"); onChange?(.script) } }
    /// Steady-mode scroll speed in points per second.
    var speed: Double { didSet { Self.defaults.set(speed, forKey: "speed") } }
    var fontSize: Double { didSet { Self.defaults.set(fontSize, forKey: "fontSize"); onChange?(.layout) } }
    var panelWidth: Double { didSet { Self.defaults.set(panelWidth, forKey: "panelWidth"); onChange?(.layout) } }
    var panelHeight: Double { didSet { Self.defaults.set(panelHeight, forKey: "panelHeight"); onChange?(.layout) } }
    var hideFromScreenShare: Bool { didSet { Self.defaults.set(hideFromScreenShare, forKey: "hideFromScreenShare"); onChange?(.layout) } }
    var appearance: AppAppearance { didSet { Self.defaults.set(appearance.rawValue, forKey: "appearance"); applyAppearance() } }
    var mode: ScrollMode { didSet { Self.defaults.set(mode.rawValue, forKey: "mode"); onChange?(.mode) } }

    var isShowing = false
    var isPaused = true
    var voiceStatus = ""

    @ObservationIgnored var onChange: ((ModelChange) -> Void)?

    init() {
        let d = Self.defaults
        script = d.string(forKey: "script") ?? Self.sampleScript
        speed = d.object(forKey: "speed") as? Double ?? 40
        fontSize = d.object(forKey: "fontSize") as? Double ?? 22
        panelWidth = d.object(forKey: "panelWidth") as? Double ?? 460
        panelHeight = d.object(forKey: "panelHeight") as? Double ?? 130
        hideFromScreenShare = d.object(forKey: "hideFromScreenShare") as? Bool ?? true
        mode = ScrollMode(rawValue: d.string(forKey: "mode") ?? "") ?? .steady
        appearance = AppAppearance(rawValue: d.string(forKey: "appearance") ?? "") ?? .system
    }

    /// The editor follows this; the notch panel always draws black to blend with the notch.
    func applyAppearance() {
        NSApp.appearance = appearance.nsAppearance
    }

    static let sampleScript = """
    Welcome to Notchling. Paste your script into this box and press Show in Notch.

    The text scrolls right under your camera, so your eyes stay on the lens while you read.

    Press the spacebar to pause or resume after clicking the notch, or press Control Option Space from any app. Scroll with your trackpad over the notch to nudge the text back or forward.

    Switch to Voice and the script moves along as you speak.
    """
}
