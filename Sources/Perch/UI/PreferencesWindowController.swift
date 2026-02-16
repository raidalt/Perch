import AppKit

final class PreferencesWindowController: NSWindowController {
    private let preferencesStore: PreferencesStore
    private let terminalPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let editorPopup = NSPopUpButton(frame: .zero, pullsDown: false)

    init(preferencesStore: PreferencesStore) {
        self.preferencesStore = preferencesStore

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 230),
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

        let root = NSStackView()
        root.translatesAutoresizingMaskIntoConstraints = false
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 14

        let subtitle = NSTextField(wrappingLabelWithString: "Configure which terminal and editor Perch uses for project actions.")
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

        for terminal in PreferredTerminal.allCases {
            terminalPopup.addItem(withTitle: terminal.title)
            terminalPopup.lastItem?.representedObject = terminal.rawValue
        }

        for editor in PreferredEditor.allCases {
            editorPopup.addItem(withTitle: editor.title)
            editorPopup.lastItem?.representedObject = editor.rawValue
        }

        root.addArrangedSubview(subtitle)
        root.addArrangedSubview(makeRow(title: "Preferred Terminal", control: terminalPopup))
        root.addArrangedSubview(makeRow(title: "Preferred Editor", control: editorPopup))

        let note = NSTextField(wrappingLabelWithString: "Ghostty is supported. Keep Terminal set to Auto to let Perch pick the best installed option.")
        note.textColor = .secondaryLabelColor
        note.lineBreakMode = .byWordWrapping
        root.addArrangedSubview(note)

        contentView.addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            root.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20)
        ])
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
        select(terminal: preferencesStore.preferredTerminal)
        select(editor: preferencesStore.preferredEditor)
    }

    private func select(terminal: PreferredTerminal) {
        selectItem(withRawValue: terminal.rawValue, in: terminalPopup)
    }

    private func select(editor: PreferredEditor) {
        selectItem(withRawValue: editor.rawValue, in: editorPopup)
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

    @objc private func terminalChanged(_ sender: NSPopUpButton) {
        guard let rawValue = sender.selectedItem?.representedObject as? String,
              let terminal = PreferredTerminal(rawValue: rawValue) else {
            return
        }
        preferencesStore.preferredTerminal = terminal
    }

    @objc private func editorChanged(_ sender: NSPopUpButton) {
        guard let rawValue = sender.selectedItem?.representedObject as? String,
              let editor = PreferredEditor(rawValue: rawValue) else {
            return
        }
        preferencesStore.preferredEditor = editor
    }
}
