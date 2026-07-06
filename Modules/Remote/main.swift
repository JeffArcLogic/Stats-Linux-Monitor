//
//  main.swift
//  Remote
//
//  Self-hosted Linux server monitoring for Stats.
//

import Cocoa
import Kit
import Security

public struct LinuxServerConfig: Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var url: String
    public var enabled: Bool
    public var displayMode: String

    public init(
        id: String = UUID().uuidString,
        name: String,
        url: String,
        enabled: Bool = true,
        displayMode: String = LinuxServerDisplayMode.compact.rawValue
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.enabled = enabled
        self.displayMode = displayMode
    }

    public var endpoint: URL? {
        var raw = self.url.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return nil }
        if !raw.contains("://") {
            raw = "http://\(raw)"
        }
        return URL(string: raw)
    }

    public var displayName: String {
        let trimmed = self.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return self.endpoint?.host ?? self.url
    }
}

public enum LinuxServerDisplayMode: String, Codable, CaseIterable {
    case compact
    case bars

    public var label: String {
        switch self {
        case .compact: return "Compact"
        case .bars: return "Bars"
        }
    }
}

public struct LinuxServerState: Codable {
    public let config: LinuxServerConfig
    public let snapshot: LinuxServerSnapshot?
    public let error: String?
    public let lastSeen: Date?

    public var online: Bool { self.snapshot != nil && self.error == nil }

    public init(config: LinuxServerConfig, snapshot: LinuxServerSnapshot?, error: String?, lastSeen: Date?) {
        self.config = config
        self.snapshot = snapshot
        self.error = error
        self.lastSeen = lastSeen
    }
}

public struct LinuxServerSnapshot: Codable {
    public let schema: String
    public let host: LinuxHostInfo
    public let timestamp: Date
    public let uptimeSec: Double
    public let cpu: LinuxCPUStats
    public let load: LinuxLoadStats
    public let memory: LinuxMemoryStats
    public let swap: LinuxSwapStats
    public let disks: [LinuxDiskStats]
    public let network: [LinuxNetStats]
    public let temperature: [LinuxSensorStats]
    public let gpu: [LinuxGPUStats]?
    public let processes: [LinuxProcessInfo]

    private enum CodingKeys: String, CodingKey {
        case schema
        case host
        case timestamp
        case uptimeSec
        case cpu
        case load
        case memory
        case swap
        case disks
        case network
        case temperature
        case gpu
        case processes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.schema = try container.decode(String.self, forKey: .schema)
        self.host = try container.decode(LinuxHostInfo.self, forKey: .host)
        self.timestamp = try container.decode(Date.self, forKey: .timestamp)
        self.uptimeSec = try container.decode(Double.self, forKey: .uptimeSec)
        self.cpu = try container.decode(LinuxCPUStats.self, forKey: .cpu)
        self.load = try container.decode(LinuxLoadStats.self, forKey: .load)
        self.memory = try container.decode(LinuxMemoryStats.self, forKey: .memory)
        self.swap = try container.decode(LinuxSwapStats.self, forKey: .swap)
        self.disks = try container.decode([LinuxDiskStats].self, forKey: .disks)
        self.network = try container.decode([LinuxNetStats].self, forKey: .network)
        self.temperature = try container.decodeIfPresent([LinuxSensorStats].self, forKey: .temperature) ?? []
        self.gpu = try container.decodeIfPresent([LinuxGPUStats].self, forKey: .gpu)
        self.processes = try container.decode([LinuxProcessInfo].self, forKey: .processes)
    }

    public var diskUsagePercent: Double {
        self.disks.map(\.usagePercent).max() ?? 0
    }

    public var networkBytesPerSecond: Double {
        self.network.map { $0.rxBytesPerSec + $0.txBytesPerSec }.reduce(0, +)
    }
}

public struct LinuxHostInfo: Codable {
    public let name: String
    public let os: String
    public let kernel: String
    public let platform: String
}

public struct LinuxCPUStats: Codable {
    public let usagePercent: Double
    public let cores: Int
    public let perCore: [Double]
}

public struct LinuxLoadStats: Codable {
    public let one: Double
    public let five: Double
    public let fifteen: Double
}

public struct LinuxMemoryStats: Codable {
    public let totalBytes: UInt64
    public let usedBytes: UInt64
    public let availableBytes: UInt64
    public let usagePercent: Double
}

public struct LinuxSwapStats: Codable {
    public let totalBytes: UInt64
    public let usedBytes: UInt64
    public let usagePercent: Double
}

public struct LinuxDiskStats: Codable {
    public let mountpoint: String
    public let device: String
    public let fsType: String
    public let totalBytes: UInt64
    public let usedBytes: UInt64
    public let freeBytes: UInt64
    public let usagePercent: Double
}

public struct LinuxNetStats: Codable {
    public let interface: String
    public let rxBytes: UInt64
    public let txBytes: UInt64
    public let rxBytesPerSec: Double
    public let txBytesPerSec: Double
}

public struct LinuxSensorStats: Codable {
    public let name: String
    public let tempCelsius: Double
}

public struct LinuxGPUStats: Codable {
    public let name: String
    public let usagePercent: Double
    public let memoryUsedMB: UInt64
    public let memoryTotalMB: UInt64
    public let tempCelsius: Double
}

public struct LinuxProcessInfo: Codable {
    public let pid: Int
    public let name: String
    public let cpuPercent: Double
    public let memoryBytes: UInt64
}

public enum LinuxServersStore {
    private static let key = "LinuxServers_list"

    public static func load() -> [LinuxServerConfig] {
        guard let data = Store.shared.data(key: key) else { return [] }
        return (try? JSONDecoder().decode([LinuxServerConfig].self, from: data)) ?? []
    }

    public static func save(_ servers: [LinuxServerConfig]) {
        if servers.isEmpty {
            Store.shared.remove(key)
            return
        }
        if let data = try? JSONEncoder().encode(servers) {
            Store.shared.set(key: key, value: data)
        }
    }
}

public enum LinuxServerKeychain {
    private static let service: String = (Bundle.main.bundleIdentifier ?? "eu.exelban.Stats") + ".linux-servers"

    public static func read(serverID: String) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: serverID,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    public static func write(_ value: String, serverID: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: serverID
        ]

        if value.isEmpty {
            SecItemDelete(query as CFDictionary)
            return
        }

        let attributes: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            attributes.forEach { addQuery[$0.key] = $0.value }
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    public static func delete(serverID: String) {
        self.write("", serverID: serverID)
    }
}

public enum LinuxServerClient {
    public static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        let plain = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = fractional.date(from: value) ?? plain.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid RFC3339 date: \(value)")
        }
        return decoder
    }()

    public static func request(for config: LinuxServerConfig, path: String) throws -> URLRequest {
        guard let endpoint = config.endpoint else {
            throw LinuxServerClientError.invalidURL
        }
        let token = LinuxServerKeychain.read(serverID: config.id)
        guard !token.isEmpty else {
            throw LinuxServerClientError.missingToken
        }
        let cleanPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        let basePath = components?.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? ""
        components?.path = "/" + [basePath, cleanPath].filter { !$0.isEmpty }.joined(separator: "/")
        guard let url = components?.url else {
            throw LinuxServerClientError.invalidURL
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    public static func fetchSnapshot(_ config: LinuxServerConfig) async -> Result<LinuxServerSnapshot, Error> {
        do {
            let request = try self.request(for: config, path: "/v1/snapshot")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return .failure(LinuxServerClientError.badStatus)
            }
            return .success(try self.decoder.decode(LinuxServerSnapshot.self, from: data))
        } catch {
            return .failure(error)
        }
    }
}

public enum LinuxServerClientError: LocalizedError {
    case invalidURL
    case missingToken
    case badStatus

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .missingToken: return "Missing token"
        case .badStatus: return "Unexpected server response"
        }
    }
}

public class Remote: Module {
    private let settingsView: Settings
    private let popupView: Popup
    private var dataReader: DataReader?
    private var statusItems: [String: LinuxServerStatusItem] = [:]

    public init() {
        self.settingsView = Settings(.remote)
        self.popupView = Popup(.remote)

        super.init(
            moduleType: .remote,
            popup: self.popupView,
            settings: self.settingsView
        )

        self.dataReader = DataReader(.remote) { [weak self] states in
            self?.callback(states)
        }

        self.settingsView.changeCallback = { [weak self] in
            self?.syncStatusItems(states: nil)
            self?.dataReader?.read()
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.handleModuleToggle),
            name: .toggleModule,
            object: nil
        )

        self.setReaders([self.dataReader])
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        self.removeStatusItems()
    }

    public override func willTerminate() {
        self.removeStatusItems()
    }

    @objc private func handleModuleToggle(_ notification: Notification) {
        guard let module = notification.userInfo?["module"] as? String, module == self.name else { return }
        if let state = notification.userInfo?["state"] as? Bool, !state {
            self.removeStatusItems()
        } else {
            self.dataReader?.read()
        }
    }

    private func callback(_ states: [LinuxServerState]?) {
        guard self.enabled else { return }
        let states = states ?? []
        DispatchQueue.main.async {
            self.popupView.callback(states)
            self.syncStatusItems(states: states)
        }
    }

    private func syncStatusItems(states: [LinuxServerState]?) {
        let configs = LinuxServersStore.load().filter(\.enabled)
        let validIDs = Set(configs.map(\.id))
        for (id, item) in self.statusItems where !validIDs.contains(id) {
            item.remove()
            self.statusItems.removeValue(forKey: id)
        }

        for config in configs where self.statusItems[config.id] == nil {
            self.statusItems[config.id] = LinuxServerStatusItem(module: self.name, config: config) { [weak self] serverID in
                self?.popupView.select(serverID: serverID)
            }
        }

        guard let states else { return }
        for state in states {
            self.statusItems[state.config.id]?.update(state)
        }
    }

    private func removeStatusItems() {
        self.statusItems.values.forEach { $0.remove() }
        self.statusItems.removeAll()
    }
}

private final class LinuxServerStatusItem: NSObject {
    private let module: String
    private var config: LinuxServerConfig
    private let statusItem: NSStatusItem
    private let view: LinuxServerTrayView
    private let select: (String) -> Void

    init(module: String, config: LinuxServerConfig, select: @escaping (String) -> Void) {
        self.module = module
        self.config = config
        self.select = select
        self.view = LinuxServerTrayView(config: config)
        self.statusItem = NSStatusBar.system.statusItem(withLength: self.view.frame.width)
        super.init()
        self.statusItem.autosaveName = "\(module)_\(config.id)"
        self.statusItem.button?.image = NSImage()
        self.statusItem.button?.toolTip = config.displayName
        self.statusItem.button?.addSubview(self.view)
        self.view.onClick = { [weak self] in self?.open() }
        self.view.onRightClick = { [weak self] event in self?.menu(event) }
    }

    func update(_ state: LinuxServerState) {
        self.config = state.config
        self.statusItem.button?.toolTip = state.config.displayName
        self.view.update(state)
        if self.statusItem.length != self.view.frame.width {
            self.statusItem.length = self.view.frame.width
        }
    }

    func remove() {
        NSStatusBar.system.removeStatusItem(self.statusItem)
    }

    private func open() {
        guard let button = self.statusItem.button, let window = button.window else { return }
        self.select(self.config.id)
        NotificationCenter.default.post(name: .togglePopup, object: nil, userInfo: [
            "module": self.module,
            "origin": window.frame.origin,
            "center": window.frame.width / 2
        ])
    }

    private func menu(_ event: NSEvent) {
        let menu = NSMenu()
        let settings = NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(NSMenuItem.separator())
        let quit = NSMenuItem(title: "Quit Stats Linux Monitor", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        NSMenu.popUpContextMenu(menu, with: event, for: self.view)
    }

    @objc private func openSettings() {
        NotificationCenter.default.post(name: .toggleSettings, object: nil, userInfo: ["module": "Linux Servers"])
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

private final class LinuxServerTrayView: NSView {
    private struct Metric {
        let label: String
        let value: Double
    }

    private enum Layout {
        static let width: CGFloat = 118
        static let sidePadding: CGFloat = 4
        static let titleY: CGFloat = 15
        static let metricLabelY: CGFloat = 9
        static let metricValueY: CGFloat = 0
        static let statusDotSize: CGFloat = 4
    }

    var onClick: (() -> Void)?
    var onRightClick: ((NSEvent) -> Void)?
    private var state: LinuxServerState?
    private var config: LinuxServerConfig

    init(config: LinuxServerConfig) {
        self.config = config
        super.init(frame: NSRect(x: 0, y: 0, width: Layout.width, height: Constants.Widget.height))
        self.wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(_ state: LinuxServerState) {
        self.state = state
        self.config = state.config
        DispatchQueue.main.async {
            self.needsDisplay = true
        }
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            self.onRightClick?(event)
            return
        }
        self.onClick?()
    }

    override func rightMouseDown(with event: NSEvent) {
        self.onRightClick?(event)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let name = self.truncatedServerName(self.config.displayName)
        let online = self.state?.online ?? false
        let snapshot = self.state?.snapshot
        let titleColor: NSColor = online ? self.primaryTextColor : .systemRed
        let muted = self.mutedTextColor
        let dotColor: NSColor = online ? .systemGreen : .systemRed

        self.drawStatusDot(color: dotColor)
        drawText(
            name,
            x: Layout.sidePadding + Layout.statusDotSize + 3,
            y: Layout.titleY,
            width: self.bounds.width - ((Layout.sidePadding * 2) + Layout.statusDotSize + 3),
            size: 6.5,
            color: titleColor,
            weight: .semibold,
            alignment: .center
        )

        if let snapshot {
            self.drawMetrics([
                Metric(label: "CPU", value: snapshot.cpu.usagePercent),
                Metric(label: "RAM", value: snapshot.memory.usagePercent),
                Metric(label: "SSD", value: snapshot.diskUsagePercent)
            ])
        } else {
            drawText(
                "offline",
                x: Layout.sidePadding,
                y: Layout.metricValueY + 1,
                width: self.bounds.width - (Layout.sidePadding * 2),
                size: 10,
                color: muted,
                weight: .semibold,
                alignment: .center
            )
        }
    }

    private func drawMetrics(_ metrics: [Metric]) {
        let width = (self.bounds.width - (Layout.sidePadding * 2)) / CGFloat(metrics.count)
        for (index, metric) in metrics.enumerated() {
            let x = Layout.sidePadding + (CGFloat(index) * width)
            drawText(
                metric.label,
                x: x,
                y: Layout.metricLabelY,
                width: width,
                size: 6,
                color: self.mutedTextColor,
                weight: .semibold,
                alignment: .center
            )
            drawText(
                "\(Int(metric.value.rounded()))%",
                x: x,
                y: Layout.metricValueY,
                width: width,
                size: 9.5,
                color: usageColor(metric.value),
                weight: .semibold,
                alignment: .center
            )
        }
    }

    private func drawStatusDot(color: NSColor) {
        color.setFill()
        let rect = NSRect(
            x: Layout.sidePadding,
            y: Layout.titleY + 2,
            width: Layout.statusDotSize,
            height: Layout.statusDotSize
        )
        NSBezierPath(ovalIn: rect).fill()
    }

    private func truncatedServerName(_ value: String) -> String {
        if value.count <= 16 { return value }
        return "\(value.prefix(13))..."
    }

    private func drawText(
        _ value: String,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        size: CGFloat,
        color: NSColor,
        weight: NSFont.Weight,
        alignment: NSTextAlignment
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        NSAttributedString(string: value, attributes: attributes).draw(in: NSRect(x: x, y: y, width: width, height: size + 2))
    }

    private var primaryTextColor: NSColor {
        isDarkMode ? .white : .textColor
    }

    private var mutedTextColor: NSColor {
        isDarkMode ? NSColor.white.withAlphaComponent(0.72) : .secondaryLabelColor
    }

    private func usageColor(_ percent: Double) -> NSColor {
        if percent >= 90 { return .systemRed }
        if percent >= 75 { return .systemOrange }
        return .controlAccentColor
    }
}
