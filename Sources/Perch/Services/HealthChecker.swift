import Foundation

enum HealthStatus {
    case unknown
    case green
    case yellow
}

final class HealthChecker {
    private struct CacheEntry {
        let status: HealthStatus
        let usesHTTPS: Bool
        let timestamp: Date
    }

    private var cache: [Int: CacheEntry] = [:]
    private let lock = NSLock()
    private let ttl: TimeInterval = 4.0
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 1.5
        config.timeoutIntervalForResource = 1.5
        session = URLSession(configuration: config)
    }

    func checkPorts(_ ports: [Int]) {
        for port in ports {
            DispatchQueue.global(qos: .utility).async {
                self.checkPort(port)
            }
        }
    }

    func status(for port: Int) -> HealthStatus {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = cache[port], Date().timeIntervalSince(entry.timestamp) < ttl else {
            return .unknown
        }
        return entry.status
    }

    func usesHTTPS(for port: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = cache[port], Date().timeIntervalSince(entry.timestamp) < ttl else {
            return false
        }
        return entry.usesHTTPS
    }

    private func checkPort(_ port: Int) {
        var usesHTTPS = false
        var status: HealthStatus = .unknown

        if let httpsURL = URL(string: "https://localhost:\(port)") {
            let (responded, _) = syncRequest(url: httpsURL)
            if responded {
                usesHTTPS = true
                status = .green
            }
        }

        if status == .unknown, let httpURL = URL(string: "http://localhost:\(port)") {
            let (responded, isServerError) = syncRequest(url: httpURL)
            if responded {
                status = .green
            } else if isServerError {
                status = .yellow
            }
        }

        lock.lock()
        cache[port] = CacheEntry(status: status, usesHTTPS: usesHTTPS, timestamp: Date())
        lock.unlock()
    }

    private func syncRequest(url: URL) -> (responded: Bool, isServerError: Bool) {
        let semaphore = DispatchSemaphore(value: 0)
        var responded = false
        var isServerError = false

        let task = session.dataTask(with: url) { _, response, error in
            if let httpResponse = response as? HTTPURLResponse {
                responded = true
                isServerError = httpResponse.statusCode >= 500
            } else if error == nil {
                responded = true
            }
            semaphore.signal()
        }
        task.resume()
        semaphore.wait()
        return (responded, isServerError)
    }
}
