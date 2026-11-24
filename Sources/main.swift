import AppKit
import ServiceManagement
import SwiftUI

// Command-line flags (used by the npm CLI, for debugging, and for README screenshots):
//   --status                      print version and launch-at-login status
//   --unregister-login-item       remove the login item and exit (run before uninstalling)
//   --show-panel                  open the panel right after launch
//   --print [seconds]             print one sample per second to stdout, no UI
//   --snapshot <file.png> [light|dark] [--seconds N]  sample N seconds (default 12), render the panel to a PNG
@MainActor
func main() throws {
    let arguments = CommandLine.arguments

    func argument(after flag: String) -> String? {
        guard let i = arguments.firstIndex(of: flag), i + 1 < arguments.count else { return nil }
        return arguments[i + 1]
    }

    func runLoop(for seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    if arguments.contains("--status") {
        let names: [SMAppService.Status: String] = [
            .enabled: "enabled", .notRegistered: "not registered",
            .requiresApproval: "requires approval (System Settings → Login Items)", .notFound: "not found",
        ]
        print("bundle: \(Bundle.main.bundlePath)")
        print("version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "?")")
        print("launch at login: \(names[LoginItem.status] ?? "unknown")")
        exit(0)
    }

    if arguments.contains("--unregister-login-item") {
        LoginItem.setEnabled(false)
        exit(0)
    }

    if arguments.contains("--print") {
        let seconds = Int(argument(after: "--print") ?? "") ?? 5
        let model = StatsModel()
        model.start()
        for _ in 0..<seconds {
            runLoop(for: 1)
            let s = model.snapshot
            let down = Format.rate(s.network.down), up = Format.rate(s.network.up)
            print("down \(down.value) \(down.unit) (\(Int(s.network.down)) B/s)  "
                + "up \(up.value) \(up.unit) (\(Int(s.network.up)) B/s)  "
                + "cpu \(Format.percent(s.cpu.total))%  "
                + "mem \(Format.percent(s.memory.fraction))% (\(s.memory.used) / \(s.memory.total) B)")
            fflush(stdout)
        }
        exit(0)
    }

    if let output = argument(after: "--snapshot") {
        let dark = arguments.contains("dark")
        let model = StatsModel()
        model.start()
        runLoop(for: TimeInterval(argument(after: "--seconds") ?? "") ?? 12)
        let view = PopoverView(model: model, forExport: true)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, dark ? .dark : .light)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write("render failed\n".data(using: .utf8)!)
            exit(1)
        }
        try png.write(to: URL(fileURLWithPath: output))
        exit(0)
    }

    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)  // menu bar only, no Dock icon
    app.run()
}

MainActor.assumeIsolated { try! main() }
