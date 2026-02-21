import Foundation

struct DevServer {
    let pid: Int32
    let port: Int
    let label: String
    let appName: String?
    let projectPath: String?
    let command: String?
    let startTime: Date?
    let cpuPercent: Double?
    let memoryMB: Int?
}
