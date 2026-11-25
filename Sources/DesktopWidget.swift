import AppKit
import SwiftUI

/// A live, widget-sized panel pinned to the desktop: above the wallpaper and desktop icons,
/// below every normal window, on all Spaces. Drag it anywhere; right-click to hide.
///
/// (WidgetKit widgets can't do this: macOS refreshes them every 15-60 minutes at best.)
@MainActor
final class DesktopWidgetController: ObservableObject {
    static let size = NSSize(width: 329, height: 155)  // macOS "medium" widget size
    static let cornerRadius: CGFloat = 22

    private static let enabledKey = "showDesktopWidget"
    private static let originKey = "desktopWidgetOrigin"  // bottom-left, global screen coordinates

    @Published private(set) var isVisible = false

    private let model: StatsModel
    private var panel: NSPanel?
    private var observers: [NSObjectProtocol] = []
    private var isRepositioning = false  // moves we make ourselves don't overwrite the user's spot

    init(model: StatsModel) {
        self.model = model
    }

    /// Re-shows the widget at launch if it was on when the app last quit.
    func restore() {
        if UserDefaults.standard.bool(forKey: Self.enabledKey) { setVisible(true) }
    }

    func setVisible(_ visible: Bool) {
        UserDefaults.standard.set(visible, forKey: Self.enabledKey)
        isVisible = visible
        if visible {
            let panel = self.panel ?? makePanel()
            position(panel)
            panel.orderFront(nil)
        } else {
            panel?.orderOut(nil)
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: Self.size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        // Just above the desktop icons, so every app window covers it, like a desktop widget.
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]

        let container = WidgetContainerView(frame: NSRect(origin: .zero, size: Self.size))
        container.onHide = { [weak self] in self?.setVisible(false) }

        let material = NSVisualEffectView(frame: container.bounds)
        material.material = .popover
        material.blendingMode = .behindWindow
        material.state = .active
        material.maskImage = .roundedMask(radius: Self.cornerRadius)
        material.autoresizingMask = [.width, .height]
        container.addSubview(material)

        let host = NSHostingView(rootView: DesktopWidgetView(model: model))
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        container.addSubview(host)
        panel.contentView = container

        // Position is saved by us, not NSWindow frame autosave: autosave only restores onto a
        // display whose *visible* frame matches exactly, so moving the menu bar to another display
        // sent the widget back to the main screen and overwrote the saved spot.
        UserDefaults.standard.removeObject(forKey: "NSWindow Frame PulseBarDesktopWidget")  // 0.2.0 dev builds

        observers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main
        ) { [weak self, weak panel] _ in
            MainActor.assumeIsolated {
                guard let self, let panel, !self.isRepositioning else { return }
                UserDefaults.standard.set(NSStringFromPoint(panel.frame.origin), forKey: Self.originKey)
            }
        })

        // A display was connected, unplugged or rearranged: go back to the saved spot if it is
        // visible again, otherwise fall back to the main screen without forgetting the saved spot.
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self, weak panel] _ in
            MainActor.assumeIsolated {
                if let self, let panel { self.position(panel) }
            }
        })

        self.panel = panel
        return panel
    }

    /// Saved spot if at least half of the widget would be on a connected display, else top-right of main.
    private func position(_ panel: NSPanel) {
        let saved = UserDefaults.standard.string(forKey: Self.originKey).map(NSPointFromString)
        let target: NSPoint
        if let saved, Self.isMostlyOnScreen(NSRect(origin: saved, size: Self.size)) {
            target = saved
        } else if let visible = NSScreen.main?.visibleFrame {
            target = NSPoint(x: visible.maxX - Self.size.width - 24, y: visible.maxY - Self.size.height - 24)
        } else {
            return
        }
        guard panel.frame.origin != target else { return }
        isRepositioning = true
        panel.setFrameOrigin(target)
        isRepositioning = false
    }

    /// Uses full display frames, not visible frames, so the menu bar's current display doesn't matter.
    private static func isMostlyOnScreen(_ frame: NSRect) -> Bool {
        NSScreen.screens.contains { screen in
            let overlap = screen.frame.intersection(frame)
            return overlap.width * overlap.height >= frame.width * frame.height * 0.5
        }
    }
}

/// Takes every click so the whole widget drags the window, and offers a right-click menu.
private final class WidgetContainerView: NSView {
    var onHide: (() -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let hide = NSMenuItem(title: "Hide Desktop Widget", action: #selector(hide), keyEquivalent: "")
        hide.target = self
        menu.addItem(hide)
        return menu
    }

    @objc private func hide() { onHide?() }
}

private extension NSImage {
    /// Stretchable rounded-rect mask for NSVisualEffectView.
    static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

// MARK: - Widget content

struct DesktopWidgetView: View {
    @ObservedObject var model: StatsModel
    /// Offscreen rendering has no window material behind it, so paint a background.
    var forExport = false

    var body: some View {
        let s = model.snapshot
        let down = Format.rate(s.network.down)
        let up = Format.rate(s.network.up)
        let shape = RoundedRectangle(cornerRadius: DesktopWidgetController.cornerRadius, style: .circular)

        Grid(horizontalSpacing: 20, verticalSpacing: 12) {
            GridRow {
                WidgetCell(title: "Download", symbol: "arrow.down", tint: Palette.download,
                           value: down.value, unit: down.unit,
                           history: s.downHistory, scaleMax: Format.networkScale(s.downHistory))
                WidgetCell(title: "Upload", symbol: "arrow.up", tint: Palette.upload,
                           value: up.value, unit: up.unit,
                           history: s.upHistory, scaleMax: Format.networkScale(s.upHistory))
            }
            GridRow {
                WidgetCell(title: "CPU", symbol: "cpu", tint: Palette.cpu,
                           value: Format.percent(s.cpu.total), unit: "%",
                           history: s.cpuHistory, scaleMax: 1)
                WidgetCell(title: "Memory", symbol: "memorychip", tint: Palette.memory,
                           value: Format.percent(s.memory.fraction), unit: "%",
                           history: s.memoryHistory, scaleMax: 1)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(width: DesktopWidgetController.size.width, height: DesktopWidgetController.size.height)
        .background {
            if forExport { shape.fill(Color(nsColor: .windowBackgroundColor)) }
        }
        .overlay(shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
    }
}

private struct WidgetCell: View {
    let title: String
    let symbol: String
    let tint: Color
    let value: String
    let unit: String
    let history: [Double]
    let scaleMax: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(tint)
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(unit)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            Sparkline(values: history, scaleMax: scaleMax, tint: tint)
                .frame(height: 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
