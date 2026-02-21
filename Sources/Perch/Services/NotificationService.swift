import UserNotifications

final class NotificationService {
    private var knownPorts: Set<Int> = []
    private var initialized = false

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func update(with servers: [DevServer]) {
        let currentPorts = Set(servers.map(\.port))

        if !initialized {
            knownPorts = currentPorts
            initialized = true
            return
        }

        let newPorts = currentPorts.subtracting(knownPorts)
        let stoppedPorts = knownPorts.subtracting(currentPorts)

        for port in newPorts {
            if let server = servers.first(where: { $0.port == port }) {
                sendNotification(title: "Server Started", body: "\(server.label) started on :\(port)")
            }
        }

        for port in stoppedPorts {
            sendNotification(title: "Server Stopped", body: "Server on :\(port) stopped")
        }

        knownPorts = currentPorts
    }

    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { _ in }
    }
}
