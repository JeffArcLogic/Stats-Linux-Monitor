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
        self.alignment = .width
        self.spacing = 6
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

        self.addFullWidthSubview(self.header(state))
        if let snapshot = state.snapshot {
            self.addFullWidthSubview(self.metricRows(snapshot))
            self.addFullWidthSubview(self.details(snapshot))
            self.addFullWidthSubview(self.processes(snapshot.processes))
        } else {
            self.addFullWidthSubview(self.offline(state))
        }
        self.resize()
    }

    private func resize() {
        let height = max(74, self.fittingSize.height)
        self.setFrameSize(NSSize(width: Constants.Popup.width, height: height))
        self.sizeCallback?(self.frame.size)
    }

    private func addFullWidthSubview(_ view: NSView) {
        self.addArrangedSubview(view)
        view.widthAnchor.constraint(equalToConstant: Constants.Popup.width).isActive = true
    }

    private func header(_ state: LinuxServerState) -> NSView {
        let view = NSStackView()
        view.orientation = .vertical
        view.alignment = .width
        view.spacing = 3
        view.edgeInsets = NSEdgeInsets(top: 9, left: 8, bottom: 7, right: 8)

        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 7

        let title = NSTextField(labelWithString: state.config.displayName)
        title.font = NSFont.systemFont(ofSize: 17, weight: .semibold)
        let dot = DotView(color: state.online ? .systemGreen : .systemRed)
        row.addArrangedSubview(dot)
        row.addArrangedSubview(title)
        row.addArrangedSubview(NSView())

        let subtitle = NSTextField(labelWithString: self.subtitle(state))
        subtitle.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byTruncatingTail

        let subtitleRow = NSStackView()
        subtitleRow.orientation = .horizontal
        subtitleRow.spacing = 7
        let statusIndent = NSView()
        statusIndent.widthAnchor.constraint(equalToConstant: 10).isActive = true
        subtitleRow.addArrangedSubview(statusIndent)
        subtitleRow.addArrangedSubview(subtitle)

        view.addArrangedSubview(row)
        view.addArrangedSubview(subtitleRow)
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
        stack.alignment = .width
        stack.spacing = 6

        let row1 = NSStackView(views: [
            MetricCard(title: "CPU", value: "\(Int(snapshot.cpu.usagePercent.rounded()))%", subtitle: String(format: "Load %.2f / %.2f", snapshot.load.one, snapshot.load.five), percent: snapshot.cpu.usagePercent),
            MetricCard(title: "Memory", value: "\(Int(snapshot.memory.usagePercent.rounded()))%", subtitle: "\(bytes(snapshot.memory.usedBytes)) / \(bytes(snapshot.memory.totalBytes))", percent: snapshot.memory.usagePercent)
        ])
        row1.orientation = .horizontal
        row1.spacing = 6
        row1.distribution = .fillEqually

        let diskSubtitle = snapshot.primaryDisk.map { "\(bytes($0.freeBytes)) free" } ?? "No disks"
        let interfaceLabel = snapshot.network.count == 1 ? "interface" : "interfaces"
        let row2 = NSStackView(views: [
            MetricCard(title: "Disk", value: "\(Int(snapshot.diskUsagePercent.rounded()))%", subtitle: diskSubtitle, percent: snapshot.diskUsagePercent),
            MetricCard(title: "Network", value: bytesPerSecond(snapshot.networkBytesPerSecond), subtitle: "\(snapshot.network.count) \(interfaceLabel)", percent: min(100, snapshot.networkBytesPerSecond / 1_000_000 * 100), accent: .systemBlue)
        ])
        row2.orientation = .horizontal
        row2.spacing = 6
        row2.distribution = .fillEqually

        stack.addArrangedSubview(row1)
        stack.addArrangedSubview(row2)
        row1.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        row2.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        if let gpu = snapshot.gpu?.first {
            let card = MetricCard(
                title: "GPU",
                value: "\(Int(gpu.usagePercent.rounded()))%",
                subtitle: "\(gpu.name) · \(Int(gpu.tempCelsius.rounded()))°C",
                percent: gpu.usagePercent,
                accent: .systemOrange
            )
            stack.addArrangedSubview(card)
            card.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return stack
    }

    private func details(_ snapshot: LinuxServerSnapshot) -> NSView {
        DashboardSection(title: "Details", rows: [
            self.detailRow("Kernel", snapshot.host.kernel),
            self.detailRow("Swap", "\(bytes(snapshot.swap.usedBytes)) / \(bytes(snapshot.swap.totalBytes)) · \(Int(snapshot.swap.usagePercent.rounded()))%"),
            self.detailRow("Temperature", snapshot.temperature.first.map { "\($0.name) · \(Int($0.tempCelsius.rounded()))°C" } ?? "No sensors")
        ])
    }

    private func processes(_ processes: [LinuxProcessInfo]) -> NSView {
        let rows = processes.prefix(6).map {
            ProcessRow(process: $0)
        }
        return DashboardSection(title: "Top Processes", trailingTitle: "MEMORY       PID", rows: rows)
    }

    private func offline(_ state: LinuxServerState) -> NSView {
        DashboardSection(title: "Connection", rows: [
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
        row.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
        row.heightAnchor.constraint(equalToConstant: 31).isActive = true

        let keyField = NSTextField(labelWithString: key)
        keyField.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        keyField.textColor = .secondaryLabelColor
        keyField.widthAnchor.constraint(equalToConstant: 80).isActive = true

        let valueField = NSTextField(labelWithString: value)
        valueField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        valueField.lineBreakMode = .byTruncatingMiddle
        valueField.alignment = .right
        valueField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

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
    init(title: String, value: String, subtitle: String, percent: Double, accent: NSColor? = nil) {
        let accent = accent ?? MetricCard.color(percent)
        super.init(frame: NSRect(x: 0, y: 0, width: 126, height: 84))
        self.wantsLayer = true
        self.layer?.cornerRadius = 8
        self.layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.075).cgColor
        self.heightAnchor.constraint(equalToConstant: 84).isActive = true
        self.widthAnchor.constraint(greaterThanOrEqualToConstant: 126).isActive = true

        let titleField = NSTextField(labelWithString: title.uppercased())
        titleField.font = NSFont.systemFont(ofSize: 9, weight: .semibold)
        titleField.textColor = accent
        titleField.lineBreakMode = .byTruncatingTail

        let valueField = NSTextField(labelWithString: value)
        valueField.font = NSFont.monospacedDigitSystemFont(ofSize: 21, weight: .semibold)
        valueField.textColor = .labelColor
        valueField.lineBreakMode = .byTruncatingTail
        valueField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let subtitleField = NSTextField(labelWithString: subtitle)
        subtitleField.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        subtitleField.textColor = .secondaryLabelColor
        subtitleField.lineBreakMode = .byTruncatingMiddle
        subtitleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let bar = ProgressBar(percent: percent, color: accent)

        for subview in [titleField, valueField, subtitleField, bar] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            self.addSubview(subview)
        }

        NSLayoutConstraint.activate([
            titleField.topAnchor.constraint(equalTo: self.topAnchor, constant: 8),
            titleField.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 9),
            titleField.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -9),

            valueField.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 1),
            valueField.leadingAnchor.constraint(equalTo: titleField.leadingAnchor),
            valueField.trailingAnchor.constraint(equalTo: titleField.trailingAnchor),

            subtitleField.leadingAnchor.constraint(equalTo: titleField.leadingAnchor),
            subtitleField.trailingAnchor.constraint(equalTo: titleField.trailingAnchor),
            subtitleField.bottomAnchor.constraint(equalTo: bar.topAnchor, constant: -5),

            bar.leadingAnchor.constraint(equalTo: titleField.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: titleField.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -7),
            bar.heightAnchor.constraint(equalToConstant: 3)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func color(_ percent: Double) -> NSColor {
        if percent >= 90 { return .systemRed }
        if percent >= 75 { return .systemOrange }
        return .systemGreen
    }
}

private final class ProgressBar: NSView {
    private let percent: Double
    private let color: NSColor

    init(percent: Double, color: NSColor) {
        self.percent = min(max(percent, 0), 100)
        self.color = color
        super.init(frame: .zero)
        self.wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.tertiaryLabelColor.withAlphaComponent(0.22).setFill()
        NSBezierPath(roundedRect: self.bounds, xRadius: 1.5, yRadius: 1.5).fill()
        let width = self.bounds.width * self.percent / 100
        guard width > 0 else { return }
        self.color.setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: width, height: self.bounds.height), xRadius: 1.5, yRadius: 1.5).fill()
    }
}

private final class DashboardSection: NSStackView {
    init(title: String, trailingTitle: String? = nil, rows: [NSView]) {
        super.init(frame: .zero)
        self.orientation = .vertical
        self.alignment = .width
        self.spacing = 0

        let header = NSStackView()
        header.orientation = .horizontal
        header.alignment = .centerY
        header.edgeInsets = NSEdgeInsets(top: 0, left: 4, bottom: 0, right: 8)
        header.heightAnchor.constraint(equalToConstant: 25).isActive = true

        let titleField = NSTextField(labelWithString: title)
        titleField.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        header.addArrangedSubview(titleField)
        header.addArrangedSubview(NSView())

        if let trailingTitle {
            let trailingField = NSTextField(labelWithString: trailingTitle)
            trailingField.font = NSFont.monospacedSystemFont(ofSize: 8, weight: .medium)
            trailingField.textColor = .tertiaryLabelColor
            trailingField.alignment = .right
            header.addArrangedSubview(trailingField)
        }
        self.addArrangedSubview(header)

        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .width
        container.spacing = 0
        container.wantsLayer = true
        container.layer?.cornerRadius = 8
        container.layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.055).cgColor
        self.addArrangedSubview(container)
        header.widthAnchor.constraint(equalTo: self.widthAnchor).isActive = true
        container.widthAnchor.constraint(equalTo: self.widthAnchor).isActive = true

        for (index, row) in rows.enumerated() {
            container.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true
            if index < rows.count - 1 {
                let separator = RowSeparator()
                container.addArrangedSubview(separator)
                separator.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateLayer() {
        super.updateLayer()
        (self.arrangedSubviews.last as? NSStackView)?.layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.055).cgColor
    }
}

private final class ProcessRow: NSStackView {
    init(process: LinuxProcessInfo) {
        super.init(frame: .zero)
        self.orientation = .horizontal
        self.alignment = .centerY
        self.spacing = 6
        self.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 9)
        self.heightAnchor.constraint(equalToConstant: 31).isActive = true

        let name = NSTextField(labelWithString: process.name)
        name.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        name.lineBreakMode = .byTruncatingTail
        name.widthAnchor.constraint(equalToConstant: 114).isActive = true

        let memory = NSTextField(labelWithString: bytes(process.memoryBytes))
        memory.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        memory.alignment = .right
        memory.widthAnchor.constraint(equalToConstant: 70).isActive = true

        let pid = NSTextField(labelWithString: String(process.pid))
        pid.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        pid.textColor = .secondaryLabelColor
        pid.alignment = .right
        pid.widthAnchor.constraint(equalToConstant: 49).isActive = true

        self.addArrangedSubview(name)
        self.addArrangedSubview(memory)
        self.addArrangedSubview(pid)
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class RowSeparator: NSView {
    init() {
        super.init(frame: .zero)
        self.heightAnchor.constraint(equalToConstant: 1).isActive = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.separatorColor.withAlphaComponent(0.28).setFill()
        NSRect(x: 10, y: 0, width: max(0, self.bounds.width - 20), height: 1).fill()
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
