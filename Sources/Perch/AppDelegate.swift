import AppKit
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let currentVersion: String

    private let preferencesStore: PreferencesStore
    private let commandRunner: CommandRunner
    private let detector: DevServerDetector
    private let editorService: EditorService
    private let terminalService: TerminalService
    private let browserService: BrowserService
    private let healthChecker = HealthChecker()
    private let notificationService = NotificationService()
    private let hotkeyService = HotkeyService()
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
        self.commandRunner = commandRunner
        self.detector = DevServerDetector(commandRunner: commandRunner)
        self.editorService = EditorService(commandRunner: commandRunner, preferencesStore: preferencesStore)
        self.terminalService = TerminalService(commandRunner: commandRunner, preferencesStore: preferencesStore)
        self.browserService = BrowserService(preferencesStore: preferencesStore)
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

        notificationService.requestAuthorization()

        if preferencesStore.hotkeyEnabled {
            hotkeyService.register { [weak self] in
                self?.statusItem?.button?.performClick(nil)
            }
        }

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

            self.healthChecker.checkPorts(servers.map(\.port))
            self.notificationService.update(with: servers)

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

        let pinnedApps = preferencesStore.pinnedApps
        if !pinnedApps.isEmpty {
            for app in pinnedApps {
                let item = NSMenuItem(title: app.name, action: #selector(launchPinnedApp(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = app
                menu.addItem(item)
            }
            menu.addItem(NSMenuItem.separator())
        }

        if servers.isEmpty {
            let empty = NSMenuItem(title: "No dev servers running", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for server in servers {
                let displayLabel = preferencesStore.customLabels["port_\(server.port)"] ?? server.label
                let appPart = server.appName.map { " [\($0)]" } ?? ""
                let uptimeSuffix = server.startTime != nil ? "  ↑\(formatUptime(server.startTime))" : ""
                let title = "\(displayLabel)\(appPart)  :\(server.port)\(uptimeSuffix)"

                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                item.image = makeDotImage(status: healthChecker.status(for: server.port))

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
                }

                sub.addItem(NSMenuItem.separator())

                let restartItem = NSMenuItem(title: "Restart", action: #selector(restartClicked(_:)), keyEquivalent: "")
                restartItem.target = self
                restartItem.representedObject = server
                sub.addItem(restartItem)

                let renameItem = NSMenuItem(title: "Rename...", action: #selector(renameClicked(_:)), keyEquivalent: "")
                renameItem.target = self
                renameItem.representedObject = server
                sub.addItem(renameItem)

                let setPathItem = NSMenuItem(title: "Set URL Path...", action: #selector(setPathClicked(_:)), keyEquivalent: "")
                setPathItem.target = self
                setPathItem.representedObject = server
                sub.addItem(setPathItem)

                sub.addItem(NSMenuItem.separator())

                if let projectPath = server.projectPath {
                    let pathItem = NSMenuItem(title: "Path: \(projectPath)", action: nil, keyEquivalent: "")
                    pathItem.isEnabled = false
                    sub.addItem(pathItem)
                }

                if let cpu = server.cpuPercent, let mem = server.memoryMB {
                    let cpuStr = String(format: "%.1f", cpu)
                    let infoItem = NSMenuItem(title: "CPU: \(cpuStr)%  •  \(mem) MB", action: nil, keyEquivalent: "")
                    infoItem.isEnabled = false
                    sub.addItem(infoItem)
                }

                sub.addItem(NSMenuItem.separator())

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

        let hotkeyItem = NSMenuItem(title: "⌃⌥P Hotkey", action: #selector(toggleHotkey), keyEquivalent: "")
        hotkeyItem.target = self
        hotkeyItem.state = preferencesStore.hotkeyEnabled ? .on : .off
        menu.addItem(hotkeyItem)

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

    private func makeDotImage(status: HealthStatus) -> NSImage {
        let size = NSSize(width: 12, height: 12)
        let image = NSImage(size: size, flipped: false) { _ in
            let color: NSColor
            switch status {
            case .green: color = .systemGreen
            case .yellow: color = .systemOrange
            case .unknown: color = .systemGray
            }
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: 1, y: 1, width: 10, height: 10)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }

    private func formatUptime(_ date: Date?) -> String {
        guard let date = date else { return "" }
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "< 1m" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if remainingMinutes == 0 { return "\(hours)h" }
        return "\(hours)h \(remainingMinutes)m"
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
        let scheme = healthChecker.usesHTTPS(for: port) ? "https" : "http"
        let customPath = preferencesStore.customPaths["port_\(port)"] ?? ""
        if let url = URL(string: "\(scheme)://localhost:\(port)\(customPath)") {
            browserService.open(url: url)
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
        let alert = NSAlert()
        alert.messageText = "Kill All Servers"
        alert.informativeText = "Are you sure you want to kill all running dev servers?"
        alert.addButton(withTitle: "Kill All")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        if alert.runModal() == .alertFirstButtonReturn {
            killAllServers()
        }
    }

    @objc private func launchPinnedApp(_ sender: NSMenuItem) {
        guard let app = sender.representedObject as? PinnedApp else { return }
        let escapedDir = commandRunner.shellEscape(app.workingDirectory)
        _ = commandRunner.runDetachedShell("cd \(escapedDir) && nohup \(app.command) &>/dev/null &")
    }

    @objc private func restartClicked(_ sender: NSMenuItem) {
        guard let server = sender.representedObject as? DevServer else { return }
        killServer(server.pid)

        guard let cmd = server.command, let path = server.projectPath else { return }
        let escapedPath = commandRunner.shellEscape(path)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            _ = self.commandRunner.runDetachedShell("cd \(escapedPath) && nohup \(cmd) &>/dev/null &")
        }
    }

    @objc private func renameClicked(_ sender: NSMenuItem) {
        guard let server = sender.representedObject as? DevServer else { return }

        let alert = NSAlert()
        alert.messageText = "Rename Server"
        alert.informativeText = "Enter a custom display name for port \(server.port):"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        field.stringValue = preferencesStore.customLabels["port_\(server.port)"] ?? server.label
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        if alert.runModal() == .alertFirstButtonReturn {
            let newName = field.stringValue.trimmingCharacters(in: .whitespaces)
            var labels = preferencesStore.customLabels
            if newName.isEmpty {
                labels.removeValue(forKey: "port_\(server.port)")
            } else {
                labels["port_\(server.port)"] = newName
            }
            preferencesStore.customLabels = labels
            updateMenu()
        }
    }

    @objc private func setPathClicked(_ sender: NSMenuItem) {
        guard let server = sender.representedObject as? DevServer else { return }

        let alert = NSAlert()
        alert.messageText = "Set URL Path"
        alert.informativeText = "Enter the URL path to append when opening port \(server.port) in a browser:"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        field.placeholderString = "/api/docs"
        field.stringValue = preferencesStore.customPaths["port_\(server.port)"] ?? ""
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        if alert.runModal() == .alertFirstButtonReturn {
            let path = field.stringValue.trimmingCharacters(in: .whitespaces)
            var paths = preferencesStore.customPaths
            if path.isEmpty {
                paths.removeValue(forKey: "port_\(server.port)")
            } else {
                paths["port_\(server.port)"] = path
            }
            preferencesStore.customPaths = paths
            updateMenu()
        }
    }

    @objc private func toggleHotkey() {
        let enabled = !preferencesStore.hotkeyEnabled
        preferencesStore.hotkeyEnabled = enabled
        if enabled {
            hotkeyService.register { [weak self] in
                self?.statusItem?.button?.performClick(nil)
            }
        } else {
            hotkeyService.unregister()
        }
        updateMenu()
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
        if preferencesStore.hotkeyEnabled {
            hotkeyService.register { [weak self] in
                self?.statusItem?.button?.performClick(nil)
            }
        } else {
            hotkeyService.unregister()
        }
        updateMenu()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
