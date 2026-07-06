//
//  popup.swift
//  Remote
//

import Cocoa
import Kit

internal class Popup: PopupWrapper {
    private var states: [String: LinuxServerState] = [:]
    private var selectedID: String?
    private var stream: LinuxServerStream?
    private var visible: Bool = false

    public init(_ module: ModuleType) {
        super.init(module, frame: NSRect(x: 0, y: 0, width: Constants.Popup.width, height: 0))
        self.orientation = .vertical
        self.spacing = Constants.Popup.spacing * 2
        self.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        self.render()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func appear() {
        super.appear()
        self.visible = true
        self.startStream()
    }

    public override func disappear() {
        super.disappear()
        self.visible = false
        self.stopStream()
    }

    public func select(serverID: String) {
        self.selectedID = serverID
        self.render()
        if self.visible {
            self.startStream()
        }
    }

    public func callback(_ values: [LinuxServerState]) {
        values.forEach { self.states[$0.config.id] = $0 }
        if self.selectedID == nil {
            self.selectedID = values.first?.config.id
        }
        self.render()
    }

    private var selectedState: LinuxServerState? {
        if let selectedID, let state = self.states[selectedID] {
            return state
        }
        return self.states.values.sorted { $0.config.displayName < $1.config.displayName }.first
    }

    private func render() {
        self.arrangedSubviews.forEach {
            self.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        guard let state = self.selectedState else {
            self.addArrangedSubview(EmptyView(height: 74, msg: localizedString("Add a Linux server in Settings")))
            self.resize()
            return
        }

        self.addArrangedSubview(self.header(state))
        if let snapshot = state.snapshot {
            self.addArrangedSubview(self.metricRows(snapshot))
            self.addArrangedSubview(self.details(snapshot))
            self.addArrangedSubview(self.processes(snapshot.processes))
        } else {
            self.addArrangedSubview(self.offline(state))
        }
        self.resize()
    }

    private func resize() {
        let height = max(74, self.fittingSize.height)
        self.setFrameSize(NSSize(width: Constants.Popup.width, height: height))
        self.sizeCallback?(self.frame.size)
    }

    private func header(_ state: LinuxServerState) -> NSView {
        let view = NSStackView()
        view.orientation = .vertical
        view.spacing = 2
        view.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 6, right: 8)

        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY

        let title = NSTextField(labelWithString: state.config.displayName)
        title.font = NSFont.systemFont(ofSize: 18, weight: .semibold)
        let dot = DotView(color: state.online ? .systemGreen : .systemRed)
        row.addArrangedSubview(dot)
        row.addArrangedSubview(title)
        row.addArrangedSubview(NSView())

        let subtitle = NSTextField(labelWithString: self.subtitle(state))
        subtitle.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        subtitle.textColor = .secondaryLabelColor

        view.addArrangedSubview(row)
        view.addArrangedSubview(subtitle)
        return view
    }

    private func subtitle(_ state: LinuxServerState) -> String {
        if let snapshot = state.snapshot {
            return "\(snapshot.host.os) · \(snapshot.cpu.cores) cores · up \(duration(snapshot.uptimeSec))"
        }
        if let seen = state.lastSeen {
            return "\(state.error ?? "Offline") · last seen \(RelativeDateTimeFormatter().localizedString(for: seen, relativeTo: Date()))"
        }
        return state.error ?? "Offline"
    }

    private func metricRows(_ snapshot: LinuxServerSnapshot) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = Constants.Popup.spacing * 2

        let row1 = NSStackView(views: [
            MetricCard(title: "CPU", value: "\(Int(snapshot.cpu.usagePercent.rounded()))%", subtitle: String(format: "Load %.2f / %.2f", snapshot.load.one, snapshot.load.five), percent: snapshot.cpu.usagePercent),
            MetricCard(title: "Memory", value: "\(Int(snapshot.memory.usagePercent.rounded()))%", subtitle: "\(bytes(snapshot.memory.usedBytes)) / \(bytes(snapshot.memory.totalBytes))", percent: snapshot.memory.usagePercent)
        ])
        row1.orientation = .horizontal
        row1.spacing = Constants.Popup.spacing * 2
        row1.distribution = .fillEqually

        let diskSubtitle = snapshot.primaryDisk.map { "\(bytes($0.usedBytes)) / \(bytes($0.totalBytes)) · \($0.mountpoint)" } ?? "No disks"
        let row2 = NSStackView(views: [
            MetricCard(title: "Disk", value: "\(Int(snapshot.diskUsagePercent.rounded()))%", subtitle: diskSubtitle, percent: snapshot.diskUsagePercent),
            MetricCard(title: "Network", value: bytesPerSecond(snapshot.networkBytesPerSecond), subtitle: "\(snapshot.network.count) interfaces", percent: min(100, snapshot.networkBytesPerSecond / 1_000_000 * 100), accent: .systemBlue)
        ])
        row2.orientation = .horizontal
        row2.spacing = Constants.Popup.spacing * 2
        row2.distribution = .fillEqually

        stack.addArrangedSubview(row1)
        stack.addArrangedSubview(row2)

        if let gpu = snapshot.gpu?.first {
            stack.addArrangedSubview(MetricCard(
                title: "GPU",
                value: "\(Int(gpu.usagePercent.rounded()))%",
                subtitle: "\(gpu.name) · \(Int(gpu.tempCelsius.rounded()))°C",
                percent: gpu.usagePercent,
                accent: .systemOrange
            ))
        }
        return stack
    }

    private func details(_ snapshot: LinuxServerSnapshot) -> NSView {
        let section = PreferencesSection(title: "Details", [
            self.detailRow("Swap", "\(Int(snapshot.swap.usagePercent.rounded()))% · \(bytes(snapshot.swap.usedBytes)) / \(bytes(snapshot.swap.totalBytes))"),
            self.detailRow("Kernel", snapshot.host.kernel),
            self.detailRow("Temperature", snapshot.temperature.first.map { "\($0.name) \(Int($0.tempCelsius.rounded()))°C" } ?? "No sensors")
        ])
        return section
    }

    private func processes(_ processes: [LinuxProcessInfo]) -> NSView {
        let rows = processes.prefix(6).map {
            self.detailRow($0.name, "\(bytes($0.memoryBytes)) · pid \($0.pid)")
        }
        return PreferencesSection(title: "Top Processes", rows)
    }

    private func offline(_ state: LinuxServerState) -> NSView {
        PreferencesSection(title: "Connection", [
            self.detailRow("Status", state.error ?? "Offline"),
            self.detailRow("URL", state.config.url),
            self.detailRow("Last seen", state.lastSeen.map { RelativeDateTimeFormatter().localizedString(for: $0, relativeTo: Date()) } ?? "Never")
        ])
    }

    private func detailRow(_ key: String, _ value: String) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.edgeInsets = NSEdgeInsets(top: 2, left: 0, bottom: 2, right: 0)

        let keyField = NSTextField(labelWithString: key)
        keyField.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        keyField.textColor = .secondaryLabelColor
        keyField.widthAnchor.constraint(equalToConstant: 78).isActive = true

        let valueField = NSTextField(labelWithString: value)
        valueField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        valueField.lineBreakMode = .byTruncatingMiddle

        row.addArrangedSubview(keyField)
        row.addArrangedSubview(valueField)
        return row
    }

    private func startStream() {
        self.stopStream()
        guard let state = self.selectedState else { return }
        let stream = LinuxServerStream(config: state.config) { [weak self] snapshot in
            guard let self else { return }
            let state = LinuxServerState(config: state.config, snapshot: snapshot, error: nil, lastSeen: snapshot.timestamp)
            DispatchQueue.main.async {
                self.states[state.config.id] = state
                self.render()
            }
        }
        self.stream = stream
        stream.start()
    }

    private func stopStream() {
        self.stream?.stop()
        self.stream = nil
    }
}

private final class MetricCard: NSView {
    private let title: String
    private let value: String
    private let subtitle: String
    private let percent: Double
    private let accent: NSColor

    init(title: String, value: String, subtitle: String, percent: Double, accent: NSColor? = nil) {
        self.title = title
        self.value = value
        self.subtitle = subtitle
        self.percent = percent
        self.accent = accent ?? MetricCard.color(percent)
        super.init(frame: NSRect(x: 0, y: 0, width: 126, height: 74))
        self.wantsLayer = true
        self.layer?.cornerRadius = Constants.Popup.radius
        self.layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.08).cgColor
        self.heightAnchor.constraint(equalToConstant: 74).isActive = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        draw(self.title, x: 8, y: 52, size: 10, color: self.accent, weight: .semibold)
        draw(self.value, x: 8, y: 28, size: 20, color: .labelColor, weight: .bold)
        draw(self.subtitle, x: 8, y: 9, size: 10, color: .secondaryLabelColor, weight: .regular)

        let bar = NSRect(x: 8, y: 4, width: self.bounds.width - 16, height: 3)
        NSColor.tertiaryLabelColor.withAlphaComponent(0.25).setFill()
        NSBezierPath(roundedRect: bar, xRadius: 1.5, yRadius: 1.5).fill()
        let fill = NSRect(x: bar.minX, y: bar.minY, width: bar.width * min(max(self.percent, 0), 100) / 100, height: bar.height)
        self.accent.setFill()
        NSBezierPath(roundedRect: fill, xRadius: 1.5, yRadius: 1.5).fill()
    }

    private func draw(_ string: String, x: CGFloat, y: CGFloat, size: CGFloat, color: NSColor, weight: NSFont.Weight) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color
        ]
        NSAttributedString(string: string, attributes: attributes).draw(in: NSRect(x: x, y: y, width: self.bounds.width - (x * 2), height: size + 4))
    }

    private static func color(_ percent: Double) -> NSColor {
        if percent >= 90 { return .systemRed }
        if percent >= 75 { return .systemOrange }
        return .systemGreen
    }
}

private final class DotView: NSView {
    private let color: NSColor

    init(color: NSColor) {
        self.color = color
        super.init(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
        self.widthAnchor.constraint(equalToConstant: 10).isActive = true
        self.heightAnchor.constraint(equalToConstant: 10).isActive = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        self.color.setFill()
        NSBezierPath(ovalIn: self.bounds.insetBy(dx: 1, dy: 1)).fill()
    }
}

private final class LinuxServerStream: NSObject, URLSessionDataDelegate {
    private let config: LinuxServerConfig
    private let onSnapshot: (LinuxServerSnapshot) -> Void
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var buffer = Data()

    init(config: LinuxServerConfig, onSnapshot: @escaping (LinuxServerSnapshot) -> Void) {
        self.config = config
        self.onSnapshot = onSnapshot
        super.init()
    }

    func start() {
        do {
            var request = try LinuxServerClient.request(for: self.config, path: "/v1/stream")
            request.timeoutInterval = .infinity
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = .infinity
            configuration.timeoutIntervalForResource = .infinity
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
            self.session = session
            self.task = session.dataTask(with: request)
            self.task?.resume()
        } catch {
            return
        }
    }

    func stop() {
        self.task?.cancel()
        self.task = nil
        self.session?.invalidateAndCancel()
        self.session = nil
        self.buffer.removeAll()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        self.buffer.append(data)
        let separator = Data("\n\n".utf8)
        while let range = self.buffer.range(of: separator) {
            let frame = self.buffer.subdata(in: 0..<range.lowerBound)
            self.buffer.removeSubrange(0..<range.upperBound)
            self.handle(frame)
        }
    }

    private func handle(_ frame: Data) {
        guard let raw = String(data: frame, encoding: .utf8) else { return }
        let dataLines = raw.split(separator: "\n")
            .filter { $0.hasPrefix("data:") }
            .map { $0.dropFirst(5).trimmingCharacters(in: .whitespaces) }
        guard !dataLines.isEmpty else { return }
        let payload = dataLines.joined(separator: "\n")
        guard let data = payload.data(using: .utf8),
              let snapshot = try? LinuxServerClient.decoder.decode(LinuxServerSnapshot.self, from: data) else { return }
        self.onSnapshot(snapshot)
    }
}

private func bytes(_ value: UInt64) -> String {
    Units(bytes: Int64(value)).getReadableMemory(style: .memory)
}

private func bytesPerSecond(_ value: Double) -> String {
    Units(bytes: Int64(value)).getReadableSpeed()
}

private func duration(_ seconds: Double) -> String {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = [.day, .hour, .minute]
    formatter.maximumUnitCount = 2
    formatter.unitsStyle = .abbreviated
    return formatter.string(from: seconds) ?? "0m"
}
