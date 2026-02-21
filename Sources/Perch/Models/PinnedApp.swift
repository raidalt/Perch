import Foundation

struct PinnedApp: Codable, Identifiable {
    var id: UUID
    var name: String
    var command: String
    var workingDirectory: String
}
