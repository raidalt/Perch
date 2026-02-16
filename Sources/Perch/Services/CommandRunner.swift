import Foundation

final class CommandRunner {
    func run(_ path: String, _ arguments: [String]) -> String? {
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

    func shellEscape(_ value: String) -> String {
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    func runDetachedShell(_ command: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-lc", command]

        do {
            try process.run()
            return true
        } catch {
            return false
        }
    }

    func commandExists(_ command: String) -> Bool {
        guard let output = run("/usr/bin/which", [command]) else { return false }
        return !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
