import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = PrompterModel()
    private var controller: NotchController!
    private var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.applyAppearance()
        controller = NotchController(model: model)
        buildMenu()

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 580),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        window.title = "Notchling"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        // An empty unified toolbar makes the title bar tall enough to center the traffic lights in the header.
        window.toolbar = NSToolbar()
        window.toolbarStyle = .unified
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: EditorView(model: model, controller: controller))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()

        // Ask up front, like voice-synced prompters do, so voice follow just works later.
        SpeechFollower.requestPermissions { _ in }

        if CommandLine.arguments.contains("--show") {
            controller.show()
            controller.togglePause()
        }
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
            let dir = CommandLine.arguments[i + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [controller, window] in
                controller?.snapshot(to: dir + "/notch.png")
                controller?.hide()
                window?.makeKeyAndOrderFront(nil)
                NSApp.activate()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    // The content view's superview is the window frame, which includes the real traffic lights.
                    if let frame = window?.contentView?.superview { writePNG(of: frame, to: dir + "/editor.png") }
                    NSApp.terminate(nil)
                }
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        window.makeKeyAndOrderFront(nil)
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    @objc private func showEditor() { window.makeKeyAndOrderFront(nil) }
    @objc private func toggleNotch() { controller.toggleShown() }
    @objc private func togglePause() { controller.togglePause() }
    @objc private func restart() { controller.restart() }

    private func buildMenu() {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Notchling", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Notchling", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Notchling", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(submenu(appMenu, "Notchling"))

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(submenu(edit, "Edit"))

        let prompter = NSMenu(title: "Prompter")
        prompter.addItem(withTitle: "Show/Hide Notch", action: #selector(toggleNotch), keyEquivalent: "\r").target = self
        prompter.addItem(withTitle: "Play/Pause", action: #selector(togglePause), keyEquivalent: "p").target = self
        prompter.addItem(withTitle: "Restart", action: #selector(restart), keyEquivalent: "r").target = self
        prompter.addItem(.separator())
        prompter.addItem(withTitle: "Script Editor", action: #selector(showEditor), keyEquivalent: "0").target = self
        main.addItem(submenu(prompter, "Prompter"))

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        main.addItem(submenu(windowMenu, "Window"))
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = main
    }

    private func submenu(_ menu: NSMenu, _ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }
}

/// Renders a view at 2x to a PNG file.
@MainActor
func writePNG(of view: NSView, to path: String) {
    let size = view.bounds.size
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
    rep.size = size
    view.cacheDisplay(in: view.bounds, to: rep)
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
}
