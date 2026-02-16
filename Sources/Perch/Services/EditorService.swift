import AppKit
import Foundation

struct ResolvedEditor {
    enum LaunchTarget {
        case shellCommand(String)
        case application(URL)
    }

    let name: String
    let launchTarget: LaunchTarget
}

final class EditorService {
    private let commandRunner: CommandRunner
    private let preferencesStore: PreferencesStore
    private var cachedResolvedEditor: ResolvedEditor?
    private var observerToken: NSObjectProtocol?

    init(commandRunner: CommandRunner, preferencesStore: PreferencesStore) {
        self.commandRunner = commandRunner
        self.preferencesStore = preferencesStore

        observerToken = NotificationCenter.default.addObserver(
            forName: .perchPreferencesDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.cachedResolvedEditor = nil
        }
    }

    deinit {
        if let observerToken {
            NotificationCenter.default.removeObserver(observerToken)
        }
    }

    func resolvedEditor() -> ResolvedEditor? {
        if let cachedResolvedEditor {
            return cachedResolvedEditor
        }

        let resolved = resolveEditor(preference: preferencesStore.preferredEditor)
        cachedResolvedEditor = resolved
        return resolved
    }

    @discardableResult
    func open(path: String) -> Bool {
        guard let editor = resolvedEditor() else { return false }

        switch editor.launchTarget {
        case .shellCommand(let command):
            return commandRunner.runDetachedShell("\(command) \(commandRunner.shellEscape(path))")
        case .application(let appURL):
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
    }

    private func resolveEditor(preference: PreferredEditor) -> ResolvedEditor? {
        switch preference {
        case .auto:
            if let configured = configuredEditor() {
                return configured
            }
            for fallback in [
                PreferredEditor.vscode,
                .cursor,
                .windsurf,
                .zed,
                .codium,
                .sublime,
                .fleet,
                .intellij,
                .webstorm,
                .pycharm,
                .goland,
                .rubymine,
                .clion,
                .xcode
            ] {
                if let resolved = resolveEditor(preference: fallback) {
                    return resolved
                }
            }
            return nil
        case .configured:
            return configuredEditor()
        case .vscode:
            return commandOrApp(command: "code", appNames: ["Visual Studio Code"], displayName: "Visual Studio Code")
        case .cursor:
            return commandOrApp(command: "cursor", appNames: ["Cursor"], displayName: "Cursor")
        case .windsurf:
            return commandOrApp(command: "windsurf", appNames: ["Windsurf"], displayName: "Windsurf")
        case .zed:
            return commandOrApp(command: "zed", appNames: ["Zed"], displayName: "Zed")
        case .codium:
            return commandOrApp(command: "codium", appNames: ["VSCodium"], displayName: "VSCodium")
        case .sublime:
            return commandOrApp(command: "subl", appNames: ["Sublime Text"], displayName: "Sublime Text")
        case .fleet:
            return commandOrApp(command: "fleet", appNames: ["Fleet"], displayName: "Fleet")
        case .intellij:
            return appOnly(appNames: ["IntelliJ IDEA"], displayName: "IntelliJ IDEA")
        case .webstorm:
            return appOnly(appNames: ["WebStorm"], displayName: "WebStorm")
        case .pycharm:
            return appOnly(appNames: ["PyCharm"], displayName: "PyCharm")
        case .goland:
            return appOnly(appNames: ["GoLand"], displayName: "GoLand")
        case .rubymine:
            return appOnly(appNames: ["RubyMine"], displayName: "RubyMine")
        case .clion:
            return appOnly(appNames: ["CLion"], displayName: "CLion")
        case .xcode:
            return appOnly(appNames: ["Xcode"], displayName: "Xcode")
        }
    }

    private func configuredEditor() -> ResolvedEditor? {
        let env = ProcessInfo.processInfo.environment

        if let visual = env["VISUAL"], !visual.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ResolvedEditor(name: "Configured Editor", launchTarget: .shellCommand(visual))
        }

        if let editor = env["EDITOR"], !editor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ResolvedEditor(name: "Configured Editor", launchTarget: .shellCommand(editor))
        }

        return nil
    }

    private func commandOrApp(command: String, appNames: [String], displayName: String) -> ResolvedEditor? {
        if commandRunner.commandExists(command) {
            return ResolvedEditor(name: displayName, launchTarget: .shellCommand(command))
        }

        if let appURL = findApplicationURL(names: appNames) {
            return ResolvedEditor(name: displayName, launchTarget: .application(appURL))
        }

        return nil
    }

    private func appOnly(appNames: [String], displayName: String) -> ResolvedEditor? {
        guard let appURL = findApplicationURL(names: appNames) else { return nil }
        return ResolvedEditor(name: displayName, launchTarget: .application(appURL))
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
