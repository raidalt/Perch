import Foundation

enum PreferredTerminal: String, CaseIterable {
    case auto
    case ghostty
    case iterm
    case terminal
    case warp
    case wezterm
    case kitty
    case alacritty

    var title: String {
        switch self {
        case .auto: return "Auto"
        case .ghostty: return "Ghostty"
        case .iterm: return "iTerm"
        case .terminal: return "Terminal"
        case .warp: return "Warp"
        case .wezterm: return "WezTerm"
        case .kitty: return "Kitty"
        case .alacritty: return "Alacritty"
        }
    }
}

enum PreferredEditor: String, CaseIterable {
    case auto
    case configured
    case vscode
    case cursor
    case windsurf
    case zed
    case codium
    case sublime
    case fleet
    case intellij
    case webstorm
    case pycharm
    case goland
    case rubymine
    case clion
    case xcode

    var title: String {
        switch self {
        case .auto: return "Auto"
        case .configured: return "Configured (VISUAL/EDITOR)"
        case .vscode: return "Visual Studio Code"
        case .cursor: return "Cursor"
        case .windsurf: return "Windsurf"
        case .zed: return "Zed"
        case .codium: return "VSCodium"
        case .sublime: return "Sublime Text"
        case .fleet: return "Fleet"
        case .intellij: return "IntelliJ IDEA"
        case .webstorm: return "WebStorm"
        case .pycharm: return "PyCharm"
        case .goland: return "GoLand"
        case .rubymine: return "RubyMine"
        case .clion: return "CLion"
        case .xcode: return "Xcode"
        }
    }
}
