import Cocoa

let currentVersion = "1.1.0"

struct DevServer {
    let pid: Int32
    let port: Int
    let label: String
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var timer: Timer?

    // MARK: - Auto-update

    var availableUpdate: (version: String, url: URL)? = nil
    var isUpdating = false

    func checkForUpdates() {
        let url = URL(string: "https://api.github.com/repos/raidalt/Perch/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("Perch/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String,
                  let assets = json["assets"] as? [[String: Any]] else { return }

            let version = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
            guard self.isNewer(version, than: currentVersion) else { return }

            for asset in assets {
                if let name = asset["name"] as? String, name.hasSuffix(".zip"),
                   let urlStr = asset["browser_download_url"] as? String,
                   let url = URL(string: urlStr) {
                    DispatchQueue.main.async {
                        self.availableUpdate = (version, url)
                        self.updateMenu()
                    }
                    return
                }
            }
        }.resume()
    }

    func isNewer(_ remote: String, than local: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let l = local.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(r.count, l.count) {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv > lv { return true }
            if rv < lv { return false }
        }
        return false
    }

    func performUpdate() {
        guard let update = availableUpdate, !isUpdating else { return }
        isUpdating = true
        updateMenu()

        URLSession.shared.downloadTask(with: update.url) { localURL, _, error in
            guard let localURL = localURL, error == nil else {
                DispatchQueue.main.async {
                    self.isUpdating = false
                    self.updateMenu()
                }
                return
            }

            let fm = FileManager.default
            let tmpDir = NSTemporaryDirectory() + "Perch-update"
            try? fm.removeItem(atPath: tmpDir)
            try? fm.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)

            let zipPath = tmpDir + "/Perch.zip"
            try? fm.moveItem(at: localURL, to: URL(fileURLWithPath: zipPath))

            // Unzip
            let unzip = Process()
            unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            unzip.arguments = ["-xk", zipPath, tmpDir]
            try? unzip.run()
            unzip.waitUntilExit()

            let newAppPath = tmpDir + "/Perch.app"
            let appPath = Bundle.main.bundlePath

            guard fm.fileExists(atPath: newAppPath) else {
                DispatchQueue.main.async {
                    self.isUpdating = false
                    self.updateMenu()
                }
                return
            }

            // Replace and relaunch
            do {
                try fm.removeItem(atPath: appPath)
                try fm.moveItem(atPath: newAppPath, toPath: appPath)
            } catch {
                DispatchQueue.main.async {
                    self.isUpdating = false
                    self.updateMenu()
                }
                return
            }

            // Relaunch via detached shell (waits for this process to exit)
            DispatchQueue.main.async {
                let relaunch = Process()
                relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
                relaunch.arguments = ["-c", "sleep 1 && open '\(appPath)'"]
                try? relaunch.run()
                NSApp.terminate(nil)
            }
        }.resume()
    }

    // MARK: - Launch at Login (LaunchAgent)

    let launchAgentLabel = "com.local.Perch"

    var launchAgentPath: String {
        let home = NSHomeDirectory()
        return "\(home)/Library/LaunchAgents/\(launchAgentLabel).plist"
    }

    var isLaunchAtLoginEnabled: Bool {
        FileManager.default.fileExists(atPath: launchAgentPath)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        if enabled {
            let appPath = Bundle.main.bundlePath
            let plist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" \
            "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>Label</key>
                <string>\(launchAgentLabel)</string>
                <key>ProgramArguments</key>
                <array>
                    <string>/usr/bin/open</string>
                    <string>-a</string>
                    <string>\(appPath)</string>
                </array>
                <key>RunAtLoad</key>
                <true/>
            </dict>
            </plist>
            """
            try? plist.write(toFile: launchAgentPath, atomically: true, encoding: .utf8)
        } else {
            try? FileManager.default.removeItem(atPath: launchAgentPath)
        }
    }

    // MARK: - Icon

    func makeIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let img = NSImage(size: size, flipped: false) { rect in
            NSColor.labelColor.setStroke()
            NSColor.labelColor.setFill()

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
        img.isTemplate = true
        return img
    }

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        updateMenu()
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            self.updateMenu()
        }

        // Check for updates on launch, then every 4 hours
        checkForUpdates()
        Timer.scheduledTimer(withTimeInterval: 4 * 3600, repeats: true) { _ in
            self.checkForUpdates()
        }
    }

    // MARK: - Command execution

    func runCommand(_ path: String, _ arguments: [String]) -> String? {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Detection

    struct ListeningProcess {
        let pid: Int32
        let port: Int
        let processName: String
    }

    func parseLsof(_ output: String) -> [ListeningProcess] {
        var results: [ListeningProcess] = []
        var currentPid: Int32? = nil
        var currentName: String? = nil

        for line in output.components(separatedBy: "\n") {
            if line.isEmpty { continue }

            let prefix = line.prefix(1)
            let value = String(line.dropFirst(1))

            switch prefix {
            case "p":
                currentPid = Int32(value)
                currentName = nil
            case "c":
                currentName = value
            case "n":
                if let pid = currentPid, let name = currentName,
                   let colonIdx = value.lastIndex(of: ":") {
                    let portStr = String(value[value.index(after: colonIdx)...])
                    if let port = Int(portStr) {
                        results.append(ListeningProcess(pid: pid, port: port, processName: name))
                    }
                }
            default:
                break
            }
        }

        return results
    }

    func detectDevServers() -> [DevServer] {
        guard let lsofOutput = runCommand("/usr/sbin/lsof", ["-iTCP", "-sTCP:LISTEN", "-nP", "-F", "pcn"]) else {
            return []
        }

        let listeners = parseLsof(lsofOutput)
        if listeners.isEmpty { return [] }

        var seen = Set<String>()
        var unique: [ListeningProcess] = []
        for l in listeners {
            let key = "\(l.pid):\(l.port)"
            if seen.insert(key).inserted {
                unique.append(l)
            }
        }

        let pids = Array(Set(unique.map { $0.pid }))
        let pidStr = pids.map { String($0) }.joined(separator: ",")
        let psOutput = runCommand("/bin/ps", ["-p", pidStr, "-o", "pid=,command="]) ?? ""

        var commandByPid: [Int32: String] = [:]
        for line in psOutput.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            let parts = trimmed.split(separator: " ", maxSplits: 1)
            if parts.count == 2, let pid = Int32(parts[0]) {
                commandByPid[pid] = String(parts[1])
            }
        }

        var servers: [DevServer] = []
        var portsByPid: [Int32: [Int]] = [:]
        for l in unique {
            portsByPid[l.pid, default: []].append(l.port)
        }

        for l in unique {
            let cmd = commandByPid[l.pid] ?? l.processName
            let cmdLower = cmd.lowercased()
            let nameLower = l.processName.lowercased()

            if let label = classifyTier1(cmd: cmdLower, name: nameLower) {
                let lowestPort = portsByPid[l.pid]?.min() ?? l.port
                if l.port == lowestPort {
                    servers.append(DevServer(pid: l.pid, port: lowestPort, label: label))
                }
            } else if let label = classifyTier2(cmd: cmdLower, name: nameLower, port: l.port) {
                let lowestPort = portsByPid[l.pid]?.min() ?? l.port
                if l.port == lowestPort {
                    servers.append(DevServer(pid: l.pid, port: lowestPort, label: label))
                }
            }
        }

        servers.sort { $0.port < $1.port }
        return servers
    }

    func classifyTier1(cmd: String, name: String) -> String? {
        if cmd.contains("next") && (cmd.contains("dev") || cmd.contains("start")) { return "Next.js" }
        if cmd.contains("next-server") || cmd.contains("next-router-worker") { return "Next.js" }
        if cmd.contains("vite") { return "Vite" }
        if cmd.contains("webpack") && cmd.contains("serve") { return "Webpack" }
        if cmd.contains("webpack-dev-server") { return "Webpack" }
        if cmd.contains("react-scripts") && cmd.contains("start") { return "React Scripts" }
        if cmd.contains("ng serve") || cmd.contains("@angular") { return "Angular" }
        if cmd.contains("nuxt") { return "Nuxt" }
        if cmd.contains("svelte-kit") || (cmd.contains("svelte") && cmd.contains("dev")) { return "SvelteKit" }
        if cmd.contains("remix") && cmd.contains("dev") { return "Remix" }
        if cmd.contains("astro") && cmd.contains("dev") { return "Astro" }
        if cmd.contains("parcel") { return "Parcel" }
        if cmd.contains("turbopack") { return "Turbopack" }
        if cmd.contains("esbuild") && cmd.contains("serve") { return "esbuild" }
        if cmd.contains("flask") { return "Flask" }
        if cmd.contains("manage.py") && cmd.contains("runserver") { return "Django" }
        if cmd.contains("django") { return "Django" }
        if cmd.contains("uvicorn") { return "Uvicorn" }
        if cmd.contains("gunicorn") { return "Gunicorn" }
        if cmd.contains("fastapi") { return "FastAPI" }
        if cmd.contains("http.server") { return "Python HTTP" }
        if cmd.contains("rails") && cmd.contains("server") { return "Rails" }
        if cmd.contains("bin/rails") { return "Rails" }
        if cmd.contains("puma") { return "Puma" }
        if cmd.contains("hugo") && cmd.contains("server") { return "Hugo" }
        if cmd.contains("jekyll") && cmd.contains("serve") { return "Jekyll" }
        if cmd.contains("gatsby") && cmd.contains("develop") { return "Gatsby" }
        if cmd.contains("eleventy") && cmd.contains("--serve") { return "Eleventy" }
        if cmd.contains("php") && cmd.contains("-S") { return "PHP Server" }
        if cmd.contains("air") && name == "air" { return "Air (Go)" }
        if cmd.contains("cargo") && cmd.contains("watch") { return "Cargo Watch" }
        if cmd.contains("live-server") { return "live-server" }
        if cmd.contains("http-server") { return "http-server" }
        if cmd.contains("bun") && cmd.contains("dev") { return "Bun Dev" }
        if cmd.contains("deno") && (cmd.contains("serve") || cmd.contains("dev")) { return "Deno" }
        if cmd.contains("nest") && cmd.contains("start") { return "NestJS" }
        if cmd.contains("nodemon") { return "Nodemon" }
        if cmd.contains("ts-node") || cmd.contains("tsx") { return "TS Node" }
        return nil
    }

    func classifyTier2(cmd: String, name: String, port: Int) -> String? {
        let devPorts: Set<Int> = [
            3000, 3001, 3002, 3003, 3004, 3005,
            4000, 4200, 4321,
            5000, 5001, 5173, 5174, 5500,
            6006,
            8000, 8001, 8080, 8081, 8443, 8888,
            9000, 9090,
            24678
        ]

        guard devPorts.contains(port) else { return nil }

        if name == "node" || cmd.hasPrefix("node ") || cmd.contains("/node ") { return "Node" }
        if name.contains("python") || cmd.contains("python") { return "Python" }
        if name == "ruby" || cmd.contains("ruby") { return "Ruby" }
        if name == "go" || cmd.hasPrefix("go ") { return "Go" }
        if name == "bun" || cmd.hasPrefix("bun ") { return "Bun" }
        if name == "deno" || cmd.hasPrefix("deno ") { return "Deno" }
        if name == "java" || cmd.contains("java") { return "Java" }
        if name == "php" || cmd.contains("php") { return "PHP" }
        return nil
    }

    // MARK: - Kill

    func killServer(_ pid: Int32) {
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

    func killAllServers() {
        let servers = detectDevServers()
        for server in servers {
            kill(server.pid, SIGTERM)
        }

        DispatchQueue.global().asyncAfter(deadline: .now() + 3.0) {
            for server in servers {
                if kill(server.pid, 0) == 0 {
                    kill(server.pid, SIGKILL)
                }
            }
            DispatchQueue.main.async { self.updateMenu() }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.updateMenu()
        }
    }

    // MARK: - Menu

    func updateMenu() {
        let servers = detectDevServers()

        DispatchQueue.main.async {
            if let button = self.statusItem.button {
                button.image = self.makeIcon()
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
                    let title = "\(server.label)  :\(server.port)  (\(server.pid))"
                    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")

                    let sub = NSMenu()

                    let openItem = NSMenuItem(title: "Open in Browser", action: #selector(self.openClicked(_:)), keyEquivalent: "")
                    openItem.target = self
                    openItem.tag = server.port
                    sub.addItem(openItem)

                    let killItem = NSMenuItem(title: "Kill", action: #selector(self.killClicked(_:)), keyEquivalent: "")
                    killItem.target = self
                    killItem.tag = Int(server.pid)
                    sub.addItem(killItem)

                    item.submenu = sub
                    menu.addItem(item)
                }

                if servers.count > 1 {
                    menu.addItem(NSMenuItem.separator())
                    let killAll = NSMenuItem(title: "Kill All", action: #selector(self.killAllClicked), keyEquivalent: "")
                    killAll.target = self
                    menu.addItem(killAll)
                }
            }

            menu.addItem(NSMenuItem.separator())

            // Update item
            if self.isUpdating {
                let updating = NSMenuItem(title: "Updating...", action: nil, keyEquivalent: "")
                updating.isEnabled = false
                menu.addItem(updating)
            } else if let update = self.availableUpdate {
                let updateItem = NSMenuItem(title: "Update to v\(update.version)", action: #selector(self.updateClicked), keyEquivalent: "")
                updateItem.target = self
                menu.addItem(updateItem)
            }

            // Launch at Login toggle
            let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(self.toggleLaunchAtLogin), keyEquivalent: "")
            loginItem.target = self
            loginItem.state = self.isLaunchAtLoginEnabled ? .on : .off
            menu.addItem(loginItem)

            let versionItem = NSMenuItem(title: "v\(currentVersion)", action: nil, keyEquivalent: "")
            versionItem.isEnabled = false
            menu.addItem(versionItem)

            menu.addItem(NSMenuItem.separator())
            menu.addItem(NSMenuItem(title: "Quit", action: #selector(self.quit), keyEquivalent: "q"))

            self.statusItem.menu = menu
        }
    }

    @objc func openClicked(_ sender: NSMenuItem) {
        let port = sender.tag
        if let url = URL(string: "http://localhost:\(port)") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func killClicked(_ sender: NSMenuItem) {
        killServer(Int32(sender.tag))
    }

    @objc func killAllClicked() {
        killAllServers()
    }

    @objc func updateClicked() {
        performUpdate()
    }

    @objc func toggleLaunchAtLogin() {
        setLaunchAtLogin(!isLaunchAtLoginEnabled)
        updateMenu()
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
