import SwiftUI

enum Palette {
    static let download = Color(red: 0.20, green: 0.60, blue: 1.00)
    static let upload = Color(red: 1.00, green: 0.45, blue: 0.35)
    static let cpu = Color(red: 0.25, green: 0.82, blue: 0.55)
    static let memory = Color(red: 0.68, green: 0.48, blue: 1.00)
}

struct PopoverView: View {
    @ObservedObject var model: StatsModel
    @ObservedObject var widget: DesktopWidgetController
    var onQuit: () -> Void = {}
    /// Offscreen rendering (README screenshots) can't draw AppKit controls, so draw a stand-in.
    var forExport = false

    @State private var loginStatus = LoginItem.status

    private var s: Snapshot { model.snapshot }

    var body: some View {
        VStack(spacing: 12) {
            header
            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    networkTile("Download", symbol: "arrow.down", tint: Palette.download,
                                rate: s.network.down, history: s.downHistory)
                    networkTile("Upload", symbol: "arrow.up", tint: Palette.upload,
                                rate: s.network.up, history: s.upHistory)
                }
                GridRow {
                    StatTile(title: "CPU", symbol: "cpu", tint: Palette.cpu,
                             value: Format.percent(s.cpu.total), unit: "%",
                             caption: "User \(Format.percent(s.cpu.user))% · Sys \(Format.percent(s.cpu.system))%",
                             history: s.cpuHistory, scaleMax: 1)
                    StatTile(title: "Memory", symbol: "memorychip", tint: Palette.memory,
                             value: Format.percent(s.memory.fraction), unit: "%",
                             caption: "\(Format.gigabytes(s.memory.used)) of \(Format.gigabytes(s.memory.total)) GB",
                             history: s.memoryHistory, scaleMax: 1)
                }
            }
            footer
        }
        .padding(14)
        .frame(width: 300)
        .onAppear { loginStatus = LoginItem.status }
    }

    private func networkTile(_ title: String, symbol: String, tint: Color,
                             rate: Double, history: [Double]) -> some View {
        let formatted = Format.rate(rate)
        return StatTile(title: title, symbol: symbol, tint: tint,
                        value: formatted.value, unit: formatted.unit,
                        caption: Format.megabits(rate), history: history,
                        scaleMax: Format.networkScale(history))
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("PulseBar")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            HStack(spacing: 4) {
                Circle().fill(Palette.cpu).frame(width: 6, height: 6)
                Text("Live · 60s")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Button(action: onQuit) {
                Image(systemName: "power")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q")
            .help("Quit PulseBar (⌘Q)")
            .padding(.leading, 4)
        }
        .padding(.horizontal, 2)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                setting("Desktop widget", isOn: Binding(
                    get: { widget.isVisible },
                    set: { widget.setVisible($0) }))
                Spacer()
                setting("Launch at login", isOn: Binding(
                    get: { loginStatus == .enabled },
                    set: { LoginItem.setEnabled($0); loginStatus = LoginItem.status }))
            }
            if loginStatus == .requiresApproval {
                Button("Launch at login needs approval in System Settings…") { LoginItem.openSystemSettings() }
                    .buttonStyle(.link)
                    .font(.system(size: 10))
            }
        }
        .padding(.horizontal, 2)
    }

    @ViewBuilder
    private func setting(_ title: String, isOn: Binding<Bool>) -> some View {
        if forExport {
            // Offscreen rendering can't draw AppKit switches; draw a look-alike.
            HStack(spacing: 6) {
                Text(title).font(.system(size: 11))
                Capsule()
                    .fill(isOn.wrappedValue ? Color.accentColor : Color.primary.opacity(0.15))
                    .frame(width: 26, height: 15)
                    .overlay(alignment: isOn.wrappedValue ? .trailing : .leading) {
                        Circle().fill(.white).padding(1.5).shadow(radius: 0.5)
                    }
            }
        } else {
            Toggle(isOn: isOn) { Text(title).font(.system(size: 11)) }
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
    }
}

struct StatTile: View {
    let title: String
    let symbol: String
    let tint: Color
    let value: String
    let unit: String
    let caption: String
    let history: [Double]
    let scaleMax: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(tint)
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(unit)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)

            Sparkline(values: history, scaleMax: scaleMax, tint: tint)
                .frame(height: 26)

            Text(caption)
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.055))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
        )
    }
}

struct Sparkline: View {
    let values: [Double]
    let scaleMax: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            let points = Self.points(values, scaleMax: scaleMax, in: geo.size)
            ZStack {
                Path { p in
                    guard let first = points.first, let last = points.last else { return }
                    p.move(to: CGPoint(x: first.x, y: geo.size.height))
                    points.forEach { p.addLine(to: $0) }
                    p.addLine(to: CGPoint(x: last.x, y: geo.size.height))
                    p.closeSubpath()
                }
                .fill(LinearGradient(colors: [tint.opacity(0.35), tint.opacity(0.02)],
                                     startPoint: .top, endPoint: .bottom))

                Path { p in
                    guard let first = points.first else { return }
                    p.move(to: first)
                    points.dropFirst().forEach { p.addLine(to: $0) }
                }
                .stroke(tint, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
    }

    private static func points(_ values: [Double], scaleMax: Double, in size: CGSize) -> [CGPoint] {
        guard values.count > 1, scaleMax > 0 else { return [] }
        // Fixed time axis, newest sample on the right edge; a young history fills in from the right.
        let step = size.width / CGFloat(Snapshot.historyLength - 1)
        let start = size.width - step * CGFloat(values.count - 1)
        let inset: CGFloat = 1  // keep the stroke inside the frame
        let usable = size.height - inset * 2
        return values.enumerated().map { i, v in
            let ratio = CGFloat(min(max(v / scaleMax, 0), 1))
            return CGPoint(x: start + CGFloat(i) * step, y: inset + usable * (1 - ratio))
        }
    }
}
