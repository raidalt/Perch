import AppKit

final class PreferencesWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let preferencesStore: PreferencesStore

    private let terminalPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let editorPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let browserPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let hotkeyCheckbox = NSButton(checkboxWithTitle: "Enable ⌃⌥P to open Perch", target: nil, action: nil)
    private let pinnedAppsTable = NSTableView()

    private var pendingNameField: NSTextField?
    private var pendingCommandField: NSTextField?
    private var pendingDirField: NSTextField?

    init(preferencesStore: PreferencesStore) {
        self.preferencesStore = preferencesStore

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 440),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Preferences"
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)

        buildUI()
        loadSelections()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showAndActivate() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        let tabView = NSTabView()
        tabView.translatesAutoresizingMaskIntoConstraints = false

        let generalItem = NSTabViewItem(identifier: "general")
        generalItem.label = "General"
        generalItem.view = buildGeneralTab()

        let pinnedItem = NSTabViewItem(identifier: "pinned")
        pinnedItem.label = "Pinned Apps"
        pinnedItem.view = buildPinnedAppsTab()

        tabView.addTabViewItem(generalItem)
        tabView.addTabViewItem(pinnedItem)

        contentView.addSubview(tabView)
        NSLayoutConstraint.activate([
            tabView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            tabView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            tabView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            tabView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        ])
    }

    private func buildGeneralTab() -> NSView {
        let view = NSView()

        let root = NSStackView()
        root.translatesAutoresizingMaskIntoConstraints = false
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 14

        let subtitle = NSTextField(wrappingLabelWithString: "Configure which terminal, editor, and browser Perch uses for project actions.")
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byWordWrapping

        terminalPopup.target = self
        terminalPopup.action = #selector(terminalChanged(_:))
        terminalPopup.translatesAutoresizingMaskIntoConstraints = false
        terminalPopup.widthAnchor.constraint(equalToConstant: 280).isActive = true

        editorPopup.target = self
        editorPopup.action = #selector(editorChanged(_:))
        editorPopup.translatesAutoresizingMaskIntoConstraints = false
        editorPopup.widthAnchor.constraint(equalToConstant: 280).isActive = true

        browserPopup.target = self
        browserPopup.action = #selector(browserChanged(_:))
        browserPopup.translatesAutoresizingMaskIntoConstraints = false
        browserPopup.widthAnchor.constraint(equalToConstant: 280).isActive = true

        for terminal in PreferredTerminal.allCases {
            terminalPopup.addItem(withTitle: terminal.title)
            terminalPopup.lastItem?.representedObject = terminal.rawValue
        }

        for editor in PreferredEditor.allCases {
            editorPopup.addItem(withTitle: editor.title)
            editorPopup.lastItem?.representedObject = editor.rawValue
        }

        for browser in PreferredBrowser.allCases {
            browserPopup.addItem(withTitle: browser.title)
            browserPopup.lastItem?.representedObject = browser.rawValue
        }

        hotkeyCheckbox.target = self
        hotkeyCheckbox.action = #selector(hotkeyChanged(_:))

        let note = NSTextField(wrappingLabelWithString: "Keep Terminal and Editor set to Auto to let Perch pick the best installed option.")
        note.textColor = .secondaryLabelColor
        note.lineBreakMode = .byWordWrapping

        root.addArrangedSubview(subtitle)
        root.addArrangedSubview(makeRow(title: "Preferred Terminal", control: terminalPopup))
        root.addArrangedSubview(makeRow(title: "Preferred Editor", control: editorPopup))
        root.addArrangedSubview(makeRow(title: "Preferred Browser", control: browserPopup))
        root.addArrangedSubview(hotkeyCheckbox)
        root.addArrangedSubview(note)

        view.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            root.topAnchor.constraint(equalTo: view.topAnchor, constant: 16)
        ])

        return view
    }

    private func buildPinnedAppsTab() -> NSView {
        let view = NSView()

        let header = NSTextField(wrappingLabelWithString: "One-click launchers that appear at the top of the menu.")
        header.textColor = .secondaryLabelColor
        header.translatesAutoresizingMaskIntoConstraints = false

        pinnedAppsTable.dataSource = self
        pinnedAppsTable.delegate = self
        pinnedAppsTable.allowsMultipleSelection = false
        pinnedAppsTable.rowHeight = 20
        pinnedAppsTable.doubleAction = #selector(editPinnedApp)
        pinnedAppsTable.target = self
        pinnedAppsTable.usesAlternatingRowBackgroundColors = true

        let nameCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameCol.title = "Name"
        nameCol.width = 130
        nameCol.dataCell = makeLabelCell()

        let commandCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("command"))
        commandCol.title = "Command"
        commandCol.width = 170
        commandCol.dataCell = makeLabelCell()

        let dirCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("directory"))
        dirCol.title = "Directory"
        dirCol.width = 200
        dirCol.dataCell = makeLabelCell()

        pinnedAppsTable.addTableColumn(nameCol)
        pinnedAppsTable.addTableColumn(commandCol)
        pinnedAppsTable.addTableColumn(dirCol)
        pinnedAppsTable.headerView = NSTableHeaderView()

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = pinnedAppsTable
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.autohidesScrollers = true

        let addButton = NSButton(title: "+", target: self, action: #selector(addPinnedApp))
        addButton.bezelStyle = .texturedSquare

        let removeButton = NSButton(title: "−", target: self, action: #selector(removePinnedApp))
        removeButton.bezelStyle = .texturedSquare

        let buttonRow = NSStackView(views: [addButton, removeButton])
        buttonRow.translatesAutoresizingMaskIntoConstraints = false
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 0

        view.addSubview(header)
        view.addSubview(scrollView)
        view.addSubview(buttonRow)

        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            header.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),

            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            scrollView.bottomAnchor.constraint(equalTo: buttonRow.topAnchor, constant: -4),

            buttonRow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            buttonRow.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12)
        ])

        return view
    }

    private func makeLabelCell() -> NSTextFieldCell {
        let cell = NSTextFieldCell()
        cell.isEditable = false
        cell.isSelectable = false
        cell.lineBreakMode = .byTruncatingTail
        return cell
    }

    private func makeRow(title: String, control: NSView) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        label.alignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: 170).isActive = true

        let row = NSStackView(views: [label, control])
        row.orientation = .horizontal
        row.spacing = 12
        row.alignment = .centerY
        return row
    }

    private func loadSelections() {
        selectItem(withRawValue: preferencesStore.preferredTerminal.rawValue, in: terminalPopup)
        selectItem(withRawValue: preferencesStore.preferredEditor.rawValue, in: editorPopup)
        selectItem(withRawValue: preferencesStore.preferredBrowser.rawValue, in: browserPopup)
        hotkeyCheckbox.state = preferencesStore.hotkeyEnabled ? .on : .off
    }

    private func selectItem(withRawValue rawValue: String, in popup: NSPopUpButton) {
        for (index, item) in popup.itemArray.enumerated() {
            if let represented = item.representedObject as? String, represented == rawValue {
                popup.selectItem(at: index)
                return
            }
        }
        popup.select(nil)
    }

    // MARK: - Pinned Apps actions

    @objc private func addPinnedApp() {
        showAddPinnedAppSheet(editing: nil, index: nil)
    }

    @objc private func editPinnedApp() {
        let row = pinnedAppsTable.selectedRow
        guard row >= 0, row < preferencesStore.pinnedApps.count else { return }
        showAddPinnedAppSheet(editing: preferencesStore.pinnedApps[row], index: row)
    }

    @objc private func removePinnedApp() {
        let row = pinnedAppsTable.selectedRow
        guard row >= 0, row < preferencesStore.pinnedApps.count else { return }
        var apps = preferencesStore.pinnedApps
        apps.remove(at: row)
        preferencesStore.pinnedApps = apps
        pinnedAppsTable.reloadData()
    }

    private func showAddPinnedAppSheet(editing: PinnedApp?, index: Int?) {
        let nameField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        nameField.placeholderString = "My API"

        let commandField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        commandField.placeholderString = "npm run dev"

        let dirField = NSTextField(frame: NSRect(x: 0, y: 0, width: 180, height: 24))
        dirField.placeholderString = "~/projects/myapp"

        if let app = editing {
            nameField.stringValue = app.name
            commandField.stringValue = app.command
            dirField.stringValue = app.workingDirectory
        }

        pendingNameField = nameField
        pendingCommandField = commandField
        pendingDirField = dirField

        let chooseButton = NSButton(title: "Choose...", target: self, action: #selector(choosePinnedAppDirectory))
        chooseButton.bezelStyle = .rounded

        func makeLabel(_ text: String) -> NSTextField {
            let lbl = NSTextField(labelWithString: text)
            lbl.alignment = .right
            lbl.translatesAutoresizingMaskIntoConstraints = false
            lbl.widthAnchor.constraint(equalToConstant: 76).isActive = true
            return lbl
        }

        let nameRow = NSStackView(views: [makeLabel("Name:"), nameField])
        nameRow.spacing = 8
        nameRow.alignment = .centerY

        let commandRow = NSStackView(views: [makeLabel("Command:"), commandField])
        commandRow.spacing = 8
        commandRow.alignment = .centerY

        let dirRow = NSStackView(views: [makeLabel("Directory:"), dirField, chooseButton])
        dirRow.spacing = 8
        dirRow.alignment = .centerY

        let stack = NSStackView(views: [nameRow, commandRow, dirRow])
        stack.orientation = .vertical
        stack.spacing = 10
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false

        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 100))
        accessory.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: accessory.leadingAnchor),
            stack.topAnchor.constraint(equalTo: accessory.topAnchor, constant: 4)
        ])

        let alert = NSAlert()
        alert.messageText = editing != nil ? "Edit Launcher" : "Add Launcher"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.accessoryView = accessory
        alert.window.initialFirstResponder = nameField

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let name = nameField.stringValue.trimmingCharacters(in: .whitespaces)
            let command = commandField.stringValue.trimmingCharacters(in: .whitespaces)
            let dir = dirField.stringValue.trimmingCharacters(in: .whitespaces)

            guard !name.isEmpty, !command.isEmpty else {
                pendingNameField = nil
                pendingCommandField = nil
                pendingDirField = nil
                return
            }

            var apps = preferencesStore.pinnedApps
            if let idx = index {
                apps[idx] = PinnedApp(
                    id: editing?.id ?? UUID(),
                    name: name,
                    command: command,
                    workingDirectory: dir
                )
            } else {
                apps.append(PinnedApp(id: UUID(), name: name, command: command, workingDirectory: dir))
            }
            preferencesStore.pinnedApps = apps
            pinnedAppsTable.reloadData()
        }

        pendingNameField = nil
        pendingCommandField = nil
        pendingDirField = nil
    }

    @objc private func choosePinnedAppDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            pendingDirField?.stringValue = url.path
        }
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        return preferencesStore.pinnedApps.count
    }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        let app = preferencesStore.pinnedApps[row]
        switch tableColumn?.identifier.rawValue {
        case "name": return app.name
        case "command": return app.command
        case "directory": return app.workingDirectory
        default: return nil
        }
    }

    // MARK: - Popup change handlers

    @objc private func terminalChanged(_ sender: NSPopUpButton) {
        guard let rawValue = sender.selectedItem?.representedObject as? String,
              let terminal = PreferredTerminal(rawValue: rawValue) else { return }
        preferencesStore.preferredTerminal = terminal
    }

    @objc private func editorChanged(_ sender: NSPopUpButton) {
        guard let rawValue = sender.selectedItem?.representedObject as? String,
              let editor = PreferredEditor(rawValue: rawValue) else { return }
        preferencesStore.preferredEditor = editor
    }

    @objc private func browserChanged(_ sender: NSPopUpButton) {
        guard let rawValue = sender.selectedItem?.representedObject as? String,
              let browser = PreferredBrowser(rawValue: rawValue) else { return }
        preferencesStore.preferredBrowser = browser
    }

    @objc private func hotkeyChanged(_ sender: NSButton) {
        preferencesStore.hotkeyEnabled = sender.state == .on
    }
}
