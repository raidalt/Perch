import AppKit
import Foundation

struct AvailableUpdate {
    let version: String
    let url: URL
}

final class UpdateManager {
    private let currentVersion: String

    private(set) var availableUpdate: AvailableUpdate?
    private(set) var isUpdating = false

    init(currentVersion: String) {
        self.currentVersion = currentVersion
    }

    func checkForUpdates(onStateChange: @escaping () -> Void) {
        guard let url = URL(string: "https://api.github.com/repos/raidalt/Perch/releases/latest") else { return }

        var request = URLRequest(url: url)
        request.setValue("Perch/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String,
                  let assets = json["assets"] as? [[String: Any]] else { return }

            let version = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
            guard self.isNewer(version, than: self.currentVersion) else { return }

            for asset in assets {
                guard let name = asset["name"] as? String,
                      name.hasSuffix(".zip"),
                      let urlString = asset["browser_download_url"] as? String,
                      let assetURL = URL(string: urlString) else {
                    continue
                }

                DispatchQueue.main.async {
                    self.availableUpdate = AvailableUpdate(version: version, url: assetURL)
                    onStateChange()
                }
                return
            }
        }.resume()
    }

    func performUpdate(onStateChange: @escaping () -> Void) {
        guard let update = availableUpdate, !isUpdating else { return }

        isUpdating = true
        onStateChange()

        URLSession.shared.downloadTask(with: update.url) { localURL, _, error in
            guard let localURL = localURL, error == nil else {
                self.finishUpdating(onStateChange)
                return
            }

            let fileManager = FileManager.default
            let tempDir = NSTemporaryDirectory() + "Perch-update"
            try? fileManager.removeItem(atPath: tempDir)
            try? fileManager.createDirectory(atPath: tempDir, withIntermediateDirectories: true)

            let zipPath = tempDir + "/Perch.zip"
            try? fileManager.moveItem(at: localURL, to: URL(fileURLWithPath: zipPath))

            let unzip = Process()
            unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            unzip.arguments = ["-xk", zipPath, tempDir]
            try? unzip.run()
            unzip.waitUntilExit()

            let newAppPath = tempDir + "/Perch.app"
            let currentAppPath = Bundle.main.bundlePath

            guard fileManager.fileExists(atPath: newAppPath) else {
                self.finishUpdating(onStateChange)
                return
            }

            do {
                try fileManager.removeItem(atPath: currentAppPath)
                try fileManager.moveItem(atPath: newAppPath, toPath: currentAppPath)
            } catch {
                self.finishUpdating(onStateChange)
                return
            }

            DispatchQueue.main.async {
                let relaunch = Process()
                relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
                relaunch.arguments = ["-c", "sleep 1 && open '\(currentAppPath)'"]
                try? relaunch.run()
                NSApp.terminate(nil)
            }
        }.resume()
    }

    private func finishUpdating(_ onStateChange: @escaping () -> Void) {
        DispatchQueue.main.async {
            self.isUpdating = false
            onStateChange()
        }
    }

    private func isNewer(_ remote: String, than local: String) -> Bool {
        let remoteParts = remote.split(separator: ".").compactMap { Int($0) }
        let localParts = local.split(separator: ".").compactMap { Int($0) }

        for index in 0..<max(remoteParts.count, localParts.count) {
            let remoteValue = index < remoteParts.count ? remoteParts[index] : 0
            let localValue = index < localParts.count ? localParts[index] : 0

            if remoteValue > localValue { return true }
            if remoteValue < localValue { return false }
        }

        return false
    }
}
