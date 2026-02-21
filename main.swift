import AppKit

let currentVersion = "1.3.0"

let app = NSApplication.shared
let delegate = AppDelegate(currentVersion: currentVersion)
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
