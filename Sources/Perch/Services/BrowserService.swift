import AppKit

struct ResolvedBrowser {
    let name: String
    let appURL: URL?
}

final class BrowserService {
    private let preferencesStore: PreferencesStore
    private var cachedResolvedBrowser: ResolvedBrowser?
    private var observerToken: NSObjectProtocol?

    init(preferencesStore: PreferencesStore) {
        self.preferencesStore = preferencesStore

        observerToken = NotificationCenter.default.addObserver(
            forName: .perchPreferencesDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.cachedResolvedBrowser = nil
        }
    }

    deinit {
        if let observerToken {
            NotificationCenter.default.removeObserver(observerToken)
        }
    }

    func resolvedBrowser() -> ResolvedBrowser? {
        if let cached = cachedResolvedBrowser { return cached }
        let resolved = resolveBrowser(preference: preferencesStore.preferredBrowser)
        cachedResolvedBrowser = resolved
        return resolved
    }

    func open(url: URL) {
        guard let browser = resolvedBrowser() else {
            NSWorkspace.shared.open(url)
            return
        }
        if let appURL = browser.appURL {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: config) { _, _ in }
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    private func resolveBrowser(preference: PreferredBrowser) -> ResolvedBrowser {
        switch preference {
        case .default:
            return ResolvedBrowser(name: "Default Browser", appURL: nil)
        case .safari:
            return appBrowser(names: ["Safari"], displayName: "Safari")
        case .chrome:
            return appBrowser(names: ["Google Chrome"], displayName: "Google Chrome")
        case .firefox:
            return appBrowser(names: ["Firefox"], displayName: "Firefox")
        case .arc:
            return appBrowser(names: ["Arc"], displayName: "Arc")
        case .brave:
            return appBrowser(names: ["Brave Browser"], displayName: "Brave")
        case .edge:
            return appBrowser(names: ["Microsoft Edge"], displayName: "Microsoft Edge")
        case .vivaldi:
            return appBrowser(names: ["Vivaldi"], displayName: "Vivaldi")
        case .opera:
            return appBrowser(names: ["Opera"], displayName: "Opera")
        }
    }

    private func appBrowser(names: [String], displayName: String) -> ResolvedBrowser {
        if let appURL = findApplicationURL(names: names) {
            return ResolvedBrowser(name: displayName, appURL: appURL)
        }
        return ResolvedBrowser(name: displayName, appURL: nil)
    }

    private func findApplicationURL(names: [String]) -> URL? {
        let home = NSHomeDirectory()
        for name in names {
            let globalURL = URL(fileURLWithPath: "/Applications/\(name).app")
            if FileManager.default.fileExists(atPath: globalURL.path) { return globalURL }
            let localURL = URL(fileURLWithPath: "\(home)/Applications/\(name).app")
            if FileManager.default.fileExists(atPath: localURL.path) { return localURL }
        }
        return nil
    }
}
