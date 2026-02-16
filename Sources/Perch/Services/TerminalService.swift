import AppKit
import Foundation

struct ResolvedTerminal {
    let name: String
    let commandTemplates: [String]
    let appURL: URL?
}

final class TerminalService {
    private let commandRunner: CommandRunner
    private let preferencesStore: PreferencesStore
    private var cachedResolvedTerminal: ResolvedTerminal?
    private var observerToken: NSObjectProtocol?

    init(commandRunner: CommandRunner, preferencesStore: PreferencesStore) {
        self.commandRunner = commandRunner
        self.preferencesStore = preferencesStore

        observerToken = NotificationCenter.default.addObserver(
            forName: .perchPreferencesDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.cachedResolvedTerminal = nil
        }
    }

    deinit {
        if let observerToken {
            NotificationCenter.default.removeObserver(observerToken)
        }
    }

    func resolvedTerminal() -> ResolvedTerminal? {
        if let cachedResolvedTerminal {
            return cachedResolvedTerminal
        }

        let resolved = resolveTerminal(preference: preferencesStore.preferredTerminal)
        cachedResolvedTerminal = resolved
        return resolved
    }

    @discardableResult
    func open(path: String) -> Bool {
        guard let terminal = resolvedTerminal() else { return false }

        let escapedPath = commandRunner.shellEscape(path)
        for template in terminal.commandTemplates {
            let command: String
            if template.contains("{path}") {
                command = template.replacingOccurrences(of: "{path}", with: escapedPath)
            } else {
                command = "\(template) \(escapedPath)"
            }

            if commandRunner.runDetachedShell(command) {
                return true
            }
        }

        guard let appURL = terminal.appURL else { return false }

        let projectURL = URL(fileURLWithPath: path)
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open(
            [projectURL],
            withApplicationAt: appURL,
            configuration: config,
            completionHandler: { _, _ in }
        )
        return true
    }

    private func resolveTerminal(preference: PreferredTerminal) -> ResolvedTerminal? {
        switch preference {
        case .auto:
            for fallback in [
                PreferredTerminal.ghostty,
                .iterm,
                .terminal,
                .warp,
                .wezterm,
                .kitty,
                .alacritty
            ] {
                if let resolved = resolveTerminal(preference: fallback) {
                    return resolved
                }
            }
            return nil
        case .ghostty:
            return commandOrApp(
                displayName: "Ghostty",
                commandCandidates: [
                    (binary: "ghostty", prefix: "ghostty --working-directory={path}"),
                    (binary: "ghostty", prefix: "ghostty --cwd={path}")
                ],
                appNames: ["Ghostty"]
            )
        case .iterm:
            return commandOrApp(
                displayName: "iTerm",
                commandCandidates: [],
                appNames: ["iTerm", "iTerm2"]
            )
        case .terminal:
            return commandOrApp(
                displayName: "Terminal",
                commandCandidates: [],
                appNames: ["Terminal"]
            )
        case .warp:
            return commandOrApp(
                displayName: "Warp",
                commandCandidates: [
                    (binary: "warp", prefix: "warp --working-directory={path}"),
                    (binary: "warp-terminal", prefix: "warp-terminal --working-directory={path}")
                ],
                appNames: ["Warp"]
            )
        case .wezterm:
            return commandOrApp(
                displayName: "WezTerm",
                commandCandidates: [
                    (binary: "wezterm", prefix: "wezterm start --cwd={path}")
                ],
                appNames: ["WezTerm"]
            )
        case .kitty:
            return commandOrApp(
                displayName: "Kitty",
                commandCandidates: [
                    (binary: "kitty", prefix: "kitty --directory={path}")
                ],
                appNames: ["kitty"]
            )
        case .alacritty:
            return commandOrApp(
                displayName: "Alacritty",
                commandCandidates: [
                    (binary: "alacritty", prefix: "alacritty --working-directory={path}")
                ],
                appNames: ["Alacritty"]
            )
        }
    }

    private func commandOrApp(
        displayName: String,
        commandCandidates: [(binary: String, prefix: String)],
        appNames: [String]
    ) -> ResolvedTerminal? {
        var templates: [String] = []
        for candidate in commandCandidates where commandRunner.commandExists(candidate.binary) {
            templates.append(candidate.prefix)
        }

        let appURL = findApplicationURL(names: appNames)

        if templates.isEmpty && appURL == nil {
            return nil
        }

        return ResolvedTerminal(name: displayName, commandTemplates: templates, appURL: appURL)
    }

    private func findApplicationURL(names: [String]) -> URL? {
        let home = NSHomeDirectory()

        for name in names {
            let globalURL = URL(fileURLWithPath: "/Applications/\(name).app")
            if FileManager.default.fileExists(atPath: globalURL.path) {
                return globalURL
            }

            let localURL = URL(fileURLWithPath: "\(home)/Applications/\(name).app")
            if FileManager.default.fileExists(atPath: localURL.path) {
                return localURL
            }
        }

        return nil
    }
}
