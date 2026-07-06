//
//  settings.swift
//  Remote
//

import Cocoa
import Kit

private let enabledColumnID = NSUserInterfaceItemIdentifier(rawValue: "enabled")
private let serverNameColumnID = NSUserInterfaceItemIdentifier(rawValue: "server-name")
private let serverURLColumnID = NSUserInterfaceItemIdentifier(rawValue: "server-url")

internal class Settings: NSStackView, Settings_v, NSTableViewDelegate, NSTableViewDataSource, NSTextFieldDelegate {
    public var changeCallback: (() -> Void) = {}

    private var servers: [LinuxServerConfig] = []
    private var selectedIndex: Int?

    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let nameField = NSTextField()
    private let urlField = NSTextField()
    private let tokenField = NSSecureTextField()
    private let enabledField = NSButton(checkboxWithTitle: localizedString("Enabled"), target: nil, action: nil)
    private let displayMode = NSPopUpButton()
    private var deleteButton: NSButton?
    private var upButton: NSButton?
    private var downButton: NSButton?

    public init(_ module: ModuleType) {
        super.init(frame: .zero)

        self.servers = LinuxServersStore.load()
        self.orientation = .vertical
        self.distribution = .fill
        self.spacing = Constants.Settings.margin

        self.setupTable()
        self.setupForm()
        self.reloadSelection()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func load(widgets: [widget_t]) {
        self.tableView.reloadData()
    }

    private func setupTable() {
        self.scrollView.documentView = self.tableView
        self.scrollView.hasVerticalScroller = true
        self.scrollView.hasHorizontalScroller = false
        self.scrollView.autohidesScrollers = true
        self.scrollView.drawsBackground = true
        self.scrollView.backgroundColor = .clear
        self.scrollView.heightAnchor.constraint(equalToConstant: 174).isActive = true

        self.tableView.delegate = self
        self.tableView.dataSource = self
        self.tableView.allowsMultipleSelection = false
        self.tableView.usesAlternatingRowBackgroundColors = true
        self.tableView.gridStyleMask = [.solidHorizontalGridLineMask]
        self.tableView.rowHeight = 30
        self.tableView.style = .plain

        let enabled = NSTableColumn(identifier: enabledColumnID)
        enabled.title = ""
        enabled.width = 36
        let name = NSTableColumn(identifier: serverNameColumnID)
        name.title = localizedString("Server")
        name.width = 150
        let url = NSTableColumn(identifier: serverURLColumnID)
        url.title = localizedString("URL")
        url.width = 300
        self.tableView.addTableColumn(enabled)
        self.tableView.addTableColumn(name)
        self.tableView.addTableColumn(url)

        self.addArrangedSubview(self.scrollView)
        self.addArrangedSubview(self.footer())
    }

    private func setupForm() {
        self.configureField(self.nameField, placeholder: localizedString("Server name"))
        self.configureField(self.urlField, placeholder: "http://server.tailnet-name.ts.net:9783")
        self.configureField(self.tokenField, placeholder: localizedString("Bearer token"))

        self.enabledField.target = self
        self.enabledField.action = #selector(self.toggleSelectedEnabled)

        self.displayMode.removeAllItems()
        LinuxServerDisplayMode.allCases.forEach { self.displayMode.addItem(withTitle: $0.label) }
        self.displayMode.target = self
        self.displayMode.action = #selector(self.changeDisplayMode)

        self.addArrangedSubview(PreferencesSection([
            PreferencesRow(localizedString("Name"), component: self.nameField),
            PreferencesRow(localizedString("URL"), component: self.urlField),
            PreferencesRow(localizedString("Token"), component: self.tokenField),
            PreferencesRow(localizedString("Display"), component: self.displayMode),
            PreferencesRow("", component: self.enabledField)
        ]))
    }

    private func configureField(_ field: NSTextField, placeholder: String) {
        field.widthAnchor.constraint(equalToConstant: 250).isActive = true
        field.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        field.textColor = .textColor
        field.isEditable = true
        field.isSelectable = true
        field.usesSingleLineMode = true
        field.maximumNumberOfLines = 1
        field.focusRingType = .none
        field.delegate = self
        field.placeholderString = placeholder
    }

    private func footer() -> NSView {
        let view = NSStackView()
        view.heightAnchor.constraint(equalToConstant: 27).isActive = true
        view.orientation = .horizontal
        view.spacing = 4

        let add = self.iconButton("plus", action: #selector(self.addServer), tooltip: localizedString("Add server"))
        let remove = self.iconButton("minus", action: #selector(self.deleteServer), tooltip: localizedString("Delete server"))
        let up = self.iconButton("chevron.up", action: #selector(self.moveServerUp), tooltip: localizedString("Move up"))
        let down = self.iconButton("chevron.down", action: #selector(self.moveServerDown), tooltip: localizedString("Move down"))
        self.deleteButton = remove
        self.upButton = up
        self.downButton = down

        view.addArrangedSubview(add)
        view.addArrangedSubview(remove)
        view.addArrangedSubview(NSView())
        view.addArrangedSubview(up)
        view.addArrangedSubview(down)
        return view
    }

    private func iconButton(_ symbol: String, action: Selector, tooltip: String) -> NSButton {
        let button = NSButton()
        button.widthAnchor.constraint(equalToConstant: 27).isActive = true
        button.heightAnchor.constraint(equalToConstant: 27).isActive = true
        button.bezelStyle = .rounded
        button.image = iconFromSymbol(name: symbol, scale: .medium)
        button.target = self
        button.action = action
        button.toolTip = tooltip
        button.focusRingType = .none
        return button
    }

    private func persist() {
        LinuxServersStore.save(self.servers)
        self.changeCallback()
    }

    private func reloadSelection() {
        let hasSelection = self.selectedIndex != nil && self.selectedIndex! < self.servers.count
        self.nameField.isEnabled = hasSelection
        self.urlField.isEnabled = hasSelection
        self.tokenField.isEnabled = hasSelection
        self.enabledField.isEnabled = hasSelection
        self.displayMode.isEnabled = hasSelection
        self.deleteButton?.isEnabled = hasSelection
        self.upButton?.isEnabled = hasSelection && self.selectedIndex != 0
        self.downButton?.isEnabled = hasSelection && self.selectedIndex != self.servers.count - 1

        guard hasSelection, let index = self.selectedIndex else {
            self.nameField.stringValue = ""
            self.urlField.stringValue = ""
            self.tokenField.stringValue = ""
            self.enabledField.state = .off
            self.displayMode.selectItem(at: 0)
            return
        }

        let server = self.servers[index]
        self.nameField.stringValue = server.name
        self.urlField.stringValue = server.url
        self.tokenField.stringValue = LinuxServerKeychain.read(serverID: server.id)
        self.enabledField.state = server.enabled ? .on : .off
        let mode = LinuxServerDisplayMode(rawValue: server.displayMode) ?? .compact
        self.displayMode.selectItem(withTitle: mode.label)
    }

    public func numberOfRows(in tableView: NSTableView) -> Int {
        self.servers.count
    }

    public func tableViewSelectionDidChange(_ notification: Notification) {
        let row = self.tableView.selectedRow
        self.selectedIndex = row >= 0 ? row : nil
        self.reloadSelection()
    }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < self.servers.count, let id = tableColumn?.identifier else { return nil }
        let server = self.servers[row]

        switch id {
        case enabledColumnID:
            let checkbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(self.toggleRowEnabled))
            checkbox.state = server.enabled ? .on : .off
            checkbox.tag = row
            return checkbox
        case serverNameColumnID:
            return self.label(server.displayName)
        case serverURLColumnID:
            return self.label(server.url)
        default:
            return nil
        }
    }

    private func label(_ value: String) -> NSTextField {
        let label = NSTextField(labelWithString: value)
        label.lineBreakMode = .byTruncatingMiddle
        return label
    }

    public func controlTextDidChange(_ obj: Notification) {
        guard let index = self.selectedIndex, index < self.servers.count else { return }
        if obj.object as? NSTextField === self.nameField {
            self.servers[index].name = self.nameField.stringValue
        } else if obj.object as? NSTextField === self.urlField {
            self.servers[index].url = self.urlField.stringValue
        } else if obj.object as? NSTextField === self.tokenField {
            LinuxServerKeychain.write(self.tokenField.stringValue, serverID: self.servers[index].id)
        }
        self.tableView.reloadData()
        self.persist()
    }

    @objc private func addServer() {
        let server = LinuxServerConfig(name: localizedString("New server"), url: "http://server.tailnet-name.ts.net:9783")
        self.servers.append(server)
        self.persist()
        self.tableView.reloadData()
        self.tableView.selectRowIndexes(IndexSet(integer: self.servers.count - 1), byExtendingSelection: false)
    }

    @objc private func deleteServer() {
        guard let index = self.selectedIndex, index < self.servers.count else { return }
        LinuxServerKeychain.delete(serverID: self.servers[index].id)
        self.servers.remove(at: index)
        self.selectedIndex = self.servers.indices.contains(index) ? index : self.servers.indices.last
        self.persist()
        self.tableView.reloadData()
        if let selectedIndex {
            self.tableView.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
        }
        self.reloadSelection()
    }

    @objc private func moveServerUp() {
        guard let index = self.selectedIndex, index > 0 else { return }
        self.servers.swapAt(index, index - 1)
        self.selectedIndex = index - 1
        self.persist()
        self.tableView.reloadData()
        self.tableView.selectRowIndexes(IndexSet(integer: index - 1), byExtendingSelection: false)
    }

    @objc private func moveServerDown() {
        guard let index = self.selectedIndex, index < self.servers.count - 1 else { return }
        self.servers.swapAt(index, index + 1)
        self.selectedIndex = index + 1
        self.persist()
        self.tableView.reloadData()
        self.tableView.selectRowIndexes(IndexSet(integer: index + 1), byExtendingSelection: false)
    }

    @objc private func toggleSelectedEnabled() {
        guard let index = self.selectedIndex, index < self.servers.count else { return }
        self.servers[index].enabled = self.enabledField.state == .on
        self.tableView.reloadData()
        self.persist()
    }

    @objc private func toggleRowEnabled(_ sender: NSButton) {
        guard sender.tag < self.servers.count else { return }
        self.servers[sender.tag].enabled = sender.state == .on
        self.persist()
        self.reloadSelection()
    }

    @objc private func changeDisplayMode() {
        guard let index = self.selectedIndex, index < self.servers.count else { return }
        let title = self.displayMode.titleOfSelectedItem ?? LinuxServerDisplayMode.compact.label
        let mode = LinuxServerDisplayMode.allCases.first(where: { $0.label == title }) ?? .compact
        self.servers[index].displayMode = mode.rawValue
        self.persist()
    }
}
