import Foundation

extension Notification.Name {
    static let perchPreferencesDidChange = Notification.Name("perchPreferencesDidChange")
}

final class PreferencesStore {
    static let shared = PreferencesStore()

    private enum Keys {
        static let preferredTerminal = "preferredTerminal"
        static let preferredEditor = "preferredEditor"
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
}
