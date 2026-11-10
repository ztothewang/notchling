import AppKit
import Carbon

/// Borderless panel that sits over the notch and can take key focus (for the
/// spacebar) without activating the app.
final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

@MainActor
final class NotchController {
    private let model: PrompterModel
    private let panel: NotchPanel
    private let view: PrompterView
    private let follower = SpeechFollower()

    init(model: PrompterModel) {
        self.model = model
        view = PrompterView(model: model)
        panel = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.contentView = view
        view.onEscape = { [weak self] in self?.hide() }

        follower.onWords = { [weak self] words in self?.view.follow(spoken: words) }
        follower.onStatus = { [weak model] status in model?.voiceStatus = status }

        model.onChange = { [weak self] change in
            guard let self else { return }
            switch change {
            case .script: self.view.rebuild()
            case .layout: self.position(); self.view.rebuild()
            case .mode: self.view.modeChanged(); self.syncFollower()
            }
        }

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.position() }
        }
        HotKey.register { [weak self] in self?.togglePause() }
    }

    func show() {
        position()
        view.rebuild()
        panel.orderFrontRegardless()
        panel.makeKey()
        panel.makeFirstResponder(view)
        model.isShowing = true
        syncFollower()
    }

    func hide() {
        panel.orderOut(nil)
        model.isShowing = false
        model.isPaused = true
        syncFollower()
    }

    func toggleShown() {
        model.isShowing ? hide() : show()
    }

    func togglePause() {
        if !model.isShowing { show() }
        model.isPaused.toggle()
    }

    func restart() {
        view.restart()
    }

    /// Writes the notch view to a PNG; used by `--snapshot <dir>` for README screenshots.
    func snapshot(to path: String) {
        writePNG(of: view, to: path)
    }

    private func syncFollower() {
        if model.isShowing && model.mode == .voice {
            follower.start()
        } else {
            follower.stop()
        }
    }

    /// Places the panel flush with the top of the notched display, centered on
    /// the camera. Displays without a notch get it just below the menu bar.
    private func position() {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main else { return }
        let notch = screen.safeAreaInsets.top
        let width = CGFloat(model.panelWidth)
        let height = CGFloat(model.panelHeight) + notch
        let top = notch > 0 ? screen.frame.maxY : screen.visibleFrame.maxY
        view.notchHeight = notch
        panel.sharingType = model.hideFromScreenShare ? .none : .readOnly
        panel.setFrame(NSRect(x: screen.frame.midX - width / 2, y: top - height, width: width, height: height), display: true)
    }
}

/// Global ⌃⌥Space hotkey via Carbon, which needs no Accessibility permission.
enum HotKey {
    nonisolated(unsafe) private static var handler: (() -> Void)?
    nonisolated(unsafe) private static var ref: EventHotKeyRef?

    static func register(_ action: @escaping @MainActor () -> Void) {
        handler = { MainActor.assumeIsolated(action) }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            HotKey.handler?()
            return noErr
        }, 1, &spec, nil, nil)
        let id = EventHotKeyID(signature: OSType(0x4559_4C4E), id: 1) // "EYLN"
        RegisterEventHotKey(UInt32(kVK_Space), UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &ref)
    }
}
