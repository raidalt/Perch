import Foundation

final class DevServerDetector {
    private let commandRunner: CommandRunner

    struct ListeningProcess {
        let pid: Int32
        let port: Int
        let processName: String
    }

    init(commandRunner: CommandRunner) {
        self.commandRunner = commandRunner
    }

    func detectDevServers() -> [DevServer] {
        guard let lsofOutput = commandRunner.run("/usr/sbin/lsof", ["-iTCP", "-sTCP:LISTEN", "-nP", "-F", "pcn"]) else {
            return []
        }

        let listeners = parseLsof(lsofOutput)
        if listeners.isEmpty { return [] }

        var seen = Set<String>()
        var unique: [ListeningProcess] = []
        for listener in listeners {
            let key = "\(listener.pid):\(listener.port)"
            if seen.insert(key).inserted {
                unique.append(listener)
            }
        }

        let pids = Array(Set(unique.map { $0.pid }))
        let pidStr = pids.map { String($0) }.joined(separator: ",")

        let psOutput = commandRunner.run("/bin/ps", ["-p", pidStr, "-o", "pid=,command="]) ?? ""
        let cwdOutput = commandRunner.run("/usr/sbin/lsof", ["-a", "-p", pidStr, "-d", "cwd", "-Fn"]) ?? ""
        let statsOutput = commandRunner.run("/bin/ps", ["-p", pidStr, "-o", "pid=,pcpu=,rss="]) ?? ""
        let lstartOutput = commandRunner.run("/bin/ps", ["-p", pidStr, "-o", "pid=,lstart="]) ?? ""

        let cwdByPid = parsePidPathMap(cwdOutput)
        let commandByPid = parsePsOutput(psOutput)
        let statsByPid = parseStatsOutput(statsOutput)
        let startTimeByPid = parseLstartOutput(lstartOutput)

        var portsByPid: [Int32: [Int]] = [:]
        for listener in unique {
            portsByPid[listener.pid, default: []].append(listener.port)
        }

        var servers: [DevServer] = []

        for listener in unique {
            let command = commandByPid[listener.pid] ?? listener.processName
            let commandLower = command.lowercased()
            let nameLower = listener.processName.lowercased()

            guard let label = classifyTier1(cmd: commandLower, name: nameLower)
                ?? classifyTier2(cmd: commandLower, name: nameLower, port: listener.port) else {
                continue
            }

            let lowestPort = portsByPid[listener.pid]?.min() ?? listener.port
            if listener.port != lowestPort { continue }

            let projectPath = normalizeProjectPath(cwdByPid[listener.pid])
            let appName = inferAppName(cwd: projectPath, command: command)
            let stats = statsByPid[listener.pid]

            servers.append(
                DevServer(
                    pid: listener.pid,
                    port: lowestPort,
                    label: label,
                    appName: appName,
                    projectPath: projectPath,
                    command: commandByPid[listener.pid],
                    startTime: startTimeByPid[listener.pid],
                    cpuPercent: stats?.cpu,
                    memoryMB: stats?.memMB
                )
            )
        }

        servers.sort { $0.port < $1.port }
        return servers
    }

    private func parsePsOutput(_ output: String) -> [Int32: String] {
        var commandByPid: [Int32: String] = [:]

        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            let parts = trimmed.split(separator: " ", maxSplits: 1)
            if parts.count == 2, let pid = Int32(parts[0]) {
                commandByPid[pid] = String(parts[1])
            }
        }

        return commandByPid
    }

    private func parseStatsOutput(_ output: String) -> [Int32: (cpu: Double, memMB: Int)] {
        var result: [Int32: (cpu: Double, memMB: Int)] = [:]

        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 3,
                  let pid = Int32(parts[0]),
                  let cpu = Double(parts[1]),
                  let rss = Int(parts[2]) else { continue }

            result[pid] = (cpu: cpu, memMB: rss / 1024)
        }

        return result
    }

    private func parseLstartOutput(_ output: String) -> [Int32: Date] {
        var result: [Int32: Date] = [:]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE MMM d HH:mm:ss yyyy"

        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2, let pid = Int32(parts[0]) else { continue }

            var dateStr = String(parts[1])
            while dateStr.contains("  ") {
                dateStr = dateStr.replacingOccurrences(of: "  ", with: " ")
            }

            if let date = formatter.date(from: dateStr) {
                result[pid] = date
            }
        }

        return result
    }

    private func parseLsof(_ output: String) -> [ListeningProcess] {
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
                if let pid = currentPid,
                   let name = currentName,
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

    private func parsePidPathMap(_ output: String) -> [Int32: String] {
        var map: [Int32: String] = [:]
        var currentPid: Int32? = nil

        for line in output.components(separatedBy: "\n") {
            if line.isEmpty { continue }

            let prefix = line.prefix(1)
            let value = String(line.dropFirst(1))

            switch prefix {
            case "p":
                currentPid = Int32(value)
            case "n":
                if let pid = currentPid, !value.isEmpty {
                    map[pid] = value
                }
            default:
                break
            }
        }

        return map
    }

    private func normalizeProjectPath(_ path: String?) -> String? {
        guard let path = path, !path.isEmpty else { return nil }
        let normalized = URL(fileURLWithPath: path).standardized.path
        if normalized == "/" { return nil }
        return normalized
    }

    private func inferAppName(cwd: String?, command: String) -> String? {
        if let normalized = normalizeProjectPath(cwd), normalized != NSHomeDirectory() {
            let candidate = URL(fileURLWithPath: normalized).lastPathComponent
            if isLikelyProjectName(candidate) {
                return candidate
            }
        }

        for rawToken in command.split(separator: " ") {
            let token = rawToken.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            guard token.hasPrefix("/") else { continue }

            let parent = URL(fileURLWithPath: token).deletingLastPathComponent().lastPathComponent
            if isLikelyProjectName(parent) {
                return parent
            }
        }

        return nil
    }

    private func isLikelyProjectName(_ value: String) -> Bool {
        if value.isEmpty { return false }

        let skip: Set<String> = [
            "users",
            "usr",
            "opt",
            "bin",
            "lib",
            "tmp",
            "var",
            "node_modules",
            "."
        ]

        return !skip.contains(value.lowercased())
    }

    private func classifyTier1(cmd: String, name: String) -> String? {
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
        if cmd.contains("php") && cmd.contains("-s") { return "PHP Server" }
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

    private func classifyTier2(cmd: String, name: String, port: Int) -> String? {
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
}
