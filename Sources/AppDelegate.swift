import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let model = StatsModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "gauge.with.dots.needle.67percent",
                                accessibilityDescription: "PulseBar")
            image?.isTemplate = true  // adapts to light/dark menu bar
            button.image = image
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        let host = NSHostingController(rootView: PopoverView(model: model) { NSApp.terminate(nil) })
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        popover.behavior = .transient  // closes on any click outside
        popover.animates = true

        model.start()
        LoginItem.enableOnFirstLaunch()

        // Open the panel once on first launch so people can see where the icon lives.
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "didShowWelcome") || CommandLine.arguments.contains("--show-panel") {
            defaults.set(true, forKey: "didShowWelcome")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.showPopover() }
        }
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        popover.isShown ? popover.performClose(sender) : showPopover()
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
}
