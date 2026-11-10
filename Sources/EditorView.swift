import SwiftUI

struct EditorView: View {
    @Bindable var model: PrompterModel
    let controller: NotchController

    /// Height of the header, which sits in the transparent title bar beside the traffic lights.
    static let headerHeight: CGFloat = 52

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.6)
            script
            controls
        }
        .frame(minWidth: 620, minHeight: 540)
        .background(Color(nsColor: .textBackgroundColor))
        .ignoresSafeArea()
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Text("Notchling")
                .font(.system(size: 13, weight: .semibold))
                .padding(.leading, 92) // clear the traffic lights
            Spacer()
            Picker("Mode", selection: $model.mode) {
                Text("Steady").tag(ScrollMode.steady)
                Text("Voice").tag(ScrollMode.voice)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 150)
            .help("Steady scrolls at a fixed speed; Voice follows along as you speak")

            CircleButton(symbol: "arrow.counterclockwise", help: "Restart from the top") { controller.restart() }
            CircleButton(symbol: model.isPaused ? "play.fill" : "pause.fill", help: "Play / pause (⌃⌥Space)") { controller.togglePause() }

            Button { controller.toggleShown() } label: {
                Label(model.isShowing ? "Hide" : "Show in Notch",
                      systemImage: model.isShowing ? "eye.slash" : "rectangle.topthird.inset.filled")
                    .font(.system(size: 12.5, weight: .semibold))
                    .padding(.horizontal, 14)
                    .frame(height: 28)
                    .foregroundStyle(.white)
                    .background(Capsule().fill(Color.accentColor))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: .command)
            .help("Show or hide the prompter (⌘↩)")
        }
        .padding(.trailing, 16)
        .frame(height: Self.headerHeight)
    }

    // MARK: Script

    private var script: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $model.script)
                .font(.system(size: 17))
                .lineSpacing(6)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 30)
                .padding(.vertical, 22)
            if model.script.isEmpty {
                Text("Paste your script here…")
                    .font(.system(size: 17))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 35)
                    .padding(.vertical, 22)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 14) {
            Grid(horizontalSpacing: 28, verticalSpacing: 12) {
                GridRow {
                    SettingSlider(symbol: "gauge.with.dots.needle.33percent", help: "Scroll speed",
                                  value: $model.speed, range: 5...200, unit: "pt/s")
                        .disabled(model.mode == .voice)
                        .opacity(model.mode == .voice ? 0.4 : 1)
                    SettingSlider(symbol: "textformat.size", help: "Text size",
                                  value: $model.fontSize, range: 14...48, unit: "pt")
                }
                GridRow {
                    SettingSlider(symbol: "arrow.left.and.right", help: "Prompter width",
                                  value: $model.panelWidth, range: 280...900, unit: "pt")
                    SettingSlider(symbol: "arrow.up.and.down", help: "Prompter height",
                                  value: $model.panelHeight, range: 60...400, unit: "pt")
                }
            }

            HStack(spacing: 14) {
                Text(stats)
                if model.mode == .voice, !model.voiceStatus.isEmpty {
                    Text("·")
                    Text(model.voiceStatus).lineLimit(1)
                }
                Spacer()
                Picker("Appearance", selection: $model.appearance) {
                    Image(systemName: "circle.lefthalf.filled").help("Match system").tag(AppAppearance.system)
                    Image(systemName: "sun.max").help("Light").tag(AppAppearance.light)
                    Image(systemName: "moon").help("Dark").tag(AppAppearance.dark)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 96)
                .help("Appearance")
                Toggle(isOn: $model.hideFromScreenShare) {
                    Text("Hide from screen share")
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .help("Keep the prompter out of screen shares and recordings")
            }
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .top) { Divider().opacity(0.6) }
    }

    private var stats: String {
        let words = model.script.split { $0.isWhitespace || $0.isNewline }.count
        let minutes = max(1, Int((Double(words) / 150).rounded()))
        return words == 0 ? "No script yet" : "\(words) words · about \(minutes) min aloud"
    }
}

private struct CircleButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.primary.opacity(hovering ? 0.12 : 0.07)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

private struct SettingSlider: View {
    let symbol: String
    let help: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let unit: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Slider(value: $value, in: range)
                .controlSize(.small)
            Text("\(Int(value)) \(unit)")
                .font(.system(size: 11.5).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .trailing)
        }
        .help(help)
    }
}
