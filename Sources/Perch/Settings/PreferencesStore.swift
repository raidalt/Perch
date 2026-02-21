import Foundation

extension Notification.Name {
    static let perchPreferencesDidChange = Notification.Name("perchPreferencesDidChange")
}

final class PreferencesStore {
    static let shared = PreferencesStore()

    private enum Keys {
        static let preferredTerminal = "preferredTerminal"
        static let preferredEditor = "preferredEditor"
        static let preferredBrowser = "preferredBrowser"
        static let customLabels = "customLabels"
        static let customPaths = "customPaths"
        static let pinnedApps = "pinnedApps"
        static let hotkeyEnabled = "hotkeyEnabled"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var preferredTerminal: PreferredTerminal {
        get {
            guard let raw = defaults.string(forKey: Keys.preferredTerminal),
                  let value = PreferredTerminal(rawValue: raw) else {
                return .auto
            }
            return value
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.preferredTerminal)
            NotificationCenter.default.post(name: .perchPreferencesDidChange, object: nil)
        }
    }

    var preferredEditor: PreferredEditor {
        get {
            guard let raw = defaults.string(forKey: Keys.preferredEditor),
                  let value = PreferredEditor(rawValue: raw) else {
                return .auto
            }
            return value
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.preferredEditor)
            NotificationCenter.default.post(name: .perchPreferencesDidChange, object: nil)
        }
    }

    var preferredBrowser: PreferredBrowser {
        get {
            guard let raw = defaults.string(forKey: Keys.preferredBrowser),
                  let value = PreferredBrowser(rawValue: raw) else {
                return .default
            }
            return value
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.preferredBrowser)
            NotificationCenter.default.post(name: .perchPreferencesDidChange, object: nil)
        }
    }

    var customLabels: [String: String] {
        get {
            guard let data = defaults.data(forKey: Keys.customLabels),
                  let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
                return [:]
            }
            return decoded
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Keys.customLabels)
            }
            NotificationCenter.default.post(name: .perchPreferencesDidChange, object: nil)
        }
    }

    var customPaths: [String: String] {
        get {
            guard let data = defaults.data(forKey: Keys.customPaths),
                  let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
                return [:]
            }
            return decoded
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Keys.customPaths)
            }
            NotificationCenter.default.post(name: .perchPreferencesDidChange, object: nil)
        }
    }

    var pinnedApps: [PinnedApp] {
        get {
            guard let data = defaults.data(forKey: Keys.pinnedApps),
                  let decoded = try? JSONDecoder().decode([PinnedApp].self, from: data) else {
                return []
            }
            return decoded
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Keys.pinnedApps)
            }
            NotificationCenter.default.post(name: .perchPreferencesDidChange, object: nil)
        }
    }

    var hotkeyEnabled: Bool {
        get { defaults.bool(forKey: Keys.hotkeyEnabled) }
        set {
            defaults.set(newValue, forKey: Keys.hotkeyEnabled)
            NotificationCenter.default.post(name: .perchPreferencesDidChange, object: nil)
        }
    }
}
