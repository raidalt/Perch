import Foundation

final class LaunchAtLoginManager {
    private let launchAgentLabel = "com.local.Perch"

    private var launchAgentPath: String {
        return "\(NSHomeDirectory())/Library/LaunchAgents/\(launchAgentLabel).plist"
    }

    var isEnabled: Bool {
        FileManager.default.fileExists(atPath: launchAgentPath)
    }

    func setEnabled(_ enabled: Bool, appPath: String) {
        if enabled {
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
}
