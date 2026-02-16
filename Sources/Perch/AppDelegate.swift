import AppKit
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let currentVersion: String

    private let preferencesStore: PreferencesStore
    private let detector: DevServerDetector
    private let editorService: EditorService
    private let terminalService: TerminalService
    private let launchAtLoginManager = LaunchAtLoginManager()
    private let updateManager: UpdateManager

    private var statusItem: NSStatusItem?
    private var refreshTimer: Timer?
    private var updateTimer: Timer?
    private var preferencesWindowController: PreferencesWindowController?

    init(currentVersion: String, preferencesStore: PreferencesStore = .shared) {
        self.currentVersion = currentVersion
        self.preferencesStore = preferencesStore

        let commandRunner = CommandRunner()
        self.detector = DevServerDetector(commandRunner: commandRunner)
        self.editorService = EditorService(commandRunner: commandRunner, preferencesStore: preferencesStore)
        self.terminalService = TerminalService(commandRunner: commandRunner, preferencesStore: preferencesStore)
        self.updateManager = UpdateManager(currentVersion: currentVersion)

        super.init()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(preferencesDidChange),
            name: .perchPreferencesDidChange,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        updateMenu()

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.updateMenu()
        }

        updateManager.checkForUpdates { [weak self] in
            self?.updateMenu()
        }

        updateTimer = Timer.scheduledTimer(withTimeInterval: 4 * 3600, repeats: true) { [weak self] _ in
            self?.updateManager.checkForUpdates {
                self?.updateMenu()
            }
        }
    }

    private func updateMenu() {
        DispatchQueue.global(qos: .utility).async {
            let servers = self.detector.detectDevServers()
            let resolvedEditor = self.editorService.resolvedEditor()
            let resolvedTerminal = self.terminalService.resolvedTerminal()

            DispatchQueue.main.async {
                self.renderMenu(
                    servers: servers,
                    resolvedEditor: resolvedEditor,
                    resolvedTerminal: resolvedTerminal
                )
            }
        }
    }

    private func renderMenu(
        servers: [DevServer],
        resolvedEditor: ResolvedEditor?,
        resolvedTerminal: ResolvedTerminal?
    ) {
        guard let statusItem else { return }

        if let button = statusItem.button {
            button.image = makeIcon()
            button.image?.isTemplate = true
            button.imagePosition = .imageLeading
            button.title = servers.isEmpty ? "0" : "\(servers.count)"
        }

        let menu = NSMenu()

        if servers.isEmpty {
            let empty = NSMenuItem(title: "No dev servers running", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for server in servers {
                let appPart = server.appName.map { " [\($0)]" } ?? ""
                let title = "\(server.label)\(appPart)  :\(server.port)  (\(server.pid))"
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")

                let sub = NSMenu()

                let openItem = NSMenuItem(title: "Open in Browser", action: #selector(openClicked(_:)), keyEquivalent: "")
                openItem.target = self
                openItem.tag = server.port
                sub.addItem(openItem)

                if let projectPath = server.projectPath {
                    let finderItem = NSMenuItem(title: "Open in Finder", action: #selector(openFinderClicked(_:)), keyEquivalent: "")
                    finderItem.target = self
                    finderItem.representedObject = projectPath
                    sub.addItem(finderItem)

                    let terminalTitle = resolvedTerminal.map { "Open in \($0.name)" } ?? "Open in Terminal"
                    let terminalItem = NSMenuItem(title: terminalTitle, action: #selector(openTerminalClicked(_:)), keyEquivalent: "")
                    terminalItem.target = self
                    terminalItem.representedObject = projectPath
                    terminalItem.isEnabled = resolvedTerminal != nil
                    sub.addItem(terminalItem)

                    let editorTitle = resolvedEditor.map { "Open in \($0.name)" } ?? "Open in Editor"
                    let editorItem = NSMenuItem(title: editorTitle, action: #selector(openEditorClicked(_:)), keyEquivalent: "")
                    editorItem.target = self
                    editorItem.representedObject = projectPath
                    editorItem.isEnabled = resolvedEditor != nil
                    sub.addItem(editorItem)

                    sub.addItem(NSMenuItem.separator())

                    let pathItem = NSMenuItem(title: "Path: \(projectPath)", action: nil, keyEquivalent: "")
                    pathItem.isEnabled = false
                    sub.addItem(pathItem)

                    sub.addItem(NSMenuItem.separator())
                }

                let killItem = NSMenuItem(title: "Kill", action: #selector(killClicked(_:)), keyEquivalent: "")
                killItem.target = self
                killItem.tag = Int(server.pid)
                sub.addItem(killItem)

                item.submenu = sub
                menu.addItem(item)
            }

            if servers.count > 1 {
                menu.addItem(NSMenuItem.separator())
                let killAll = NSMenuItem(title: "Kill All", action: #selector(killAllClicked), keyEquivalent: "")
                killAll.target = self
                menu.addItem(killAll)
            }
        }

        menu.addItem(NSMenuItem.separator())

        if updateManager.isUpdating {
            let updating = NSMenuItem(title: "Updating...", action: nil, keyEquivalent: "")
            updating.isEnabled = false
            menu.addItem(updating)
        } else if let update = updateManager.availableUpdate {
            let updateItem = NSMenuItem(title: "Update to v\(update.version)", action: #selector(updateClicked), keyEquivalent: "")
            updateItem.target = self
            menu.addItem(updateItem)
        }

        let preferencesItem = NSMenuItem(title: "Preferences...", action: #selector(openPreferences), keyEquivalent: ",")
        preferencesItem.target = self
        menu.addItem(preferencesItem)

        let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = launchAtLoginManager.isEnabled ? .on : .off
        menu.addItem(loginItem)

        let versionItem = NSMenuItem(title: "v\(currentVersion)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func makeIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            NSColor.labelColor.setStroke()

            let path = NSBezierPath()
            path.lineWidth = 1.5
            path.lineCapStyle = .round
            path.lineJoinStyle = .round

            path.move(to: NSPoint(x: 3, y: 13))
            path.line(to: NSPoint(x: 8, y: 9))
            path.line(to: NSPoint(x: 3, y: 5))
            path.stroke()

            let underline = NSBezierPath()
            underline.lineWidth = 1.5
            underline.lineCapStyle = .round
            underline.move(to: NSPoint(x: 10, y: 5))
            underline.line(to: NSPoint(x: 15, y: 5))
            underline.stroke()

            return true
        }

        image.isTemplate = true
        return image
    }

    private func killServer(_ pid: Int32) {
        kill(pid, SIGTERM)

        DispatchQueue.global().asyncAfter(deadline: .now() + 3.0) {
            if kill(pid, 0) == 0 {
                kill(pid, SIGKILL)
            }
            DispatchQueue.main.async { self.updateMenu() }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.updateMenu()
        }
    }

    private func killAllServers() {
        let servers = detector.detectDevServers()
        for server in servers {
            kill(server.pid, SIGTERM)
        }

        DispatchQueue.global().asyncAfter(deadline: .now() + 3.0) {
            for server in servers where kill(server.pid, 0) == 0 {
                kill(server.pid, SIGKILL)
            }
            DispatchQueue.main.async { self.updateMenu() }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.updateMenu()
        }
    }

    @objc private func openClicked(_ sender: NSMenuItem) {
        let port = sender.tag
        if let url = URL(string: "http://localhost:\(port)") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openFinderClicked(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    @objc private func openTerminalClicked(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        _ = terminalService.open(path: path)
    }

    @objc private func openEditorClicked(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        _ = editorService.open(path: path)
    }

    @objc private func killClicked(_ sender: NSMenuItem) {
        killServer(Int32(sender.tag))
    }

    @objc private func killAllClicked() {
        killAllServers()
    }

    @objc private func updateClicked() {
        updateManager.performUpdate { [weak self] in
            self?.updateMenu()
        }
    }

    @objc private func toggleLaunchAtLogin() {
        let enabled = !launchAtLoginManager.isEnabled
        launchAtLoginManager.setEnabled(enabled, appPath: Bundle.main.bundlePath)
        updateMenu()
    }

    @objc private func openPreferences() {
        if preferencesWindowController == nil {
            preferencesWindowController = PreferencesWindowController(preferencesStore: preferencesStore)
        }
        preferencesWindowController?.showAndActivate()
    }

    @objc private func preferencesDidChange() {
        updateMenu()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
