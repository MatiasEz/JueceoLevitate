import Foundation

struct AppData: Codable, Sendable {
    var sourceName: String
    var blocks: [DanceBlock]
    var routines: [Routine]
    var templates: [JudgingTemplate]
    var judges: [String]
}

struct DanceBlock: Codable, Identifiable, Sendable {
    var id: String { name }
    let name: String
    let title: String
    let routines: [Routine]
}

struct Routine: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let block: String
    let name: String
    let academy: String
    let division: String
    let genre: String
    let level: String
    let category: String
    let choreographer: String
    let state: String
    let time: String
    let duration: String
}

struct JudgingTemplate: Codable, Identifiable, Hashable, Sendable {
    var id: String { genre.normalizedKey }
    let genre: String
    let title: String
    let maxScore: Double
    let criteria: [Criterion]
}

struct Criterion: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let section: String
    let label: String
    let maxScore: Double
}

struct RoutineResult: Identifiable, Sendable {
    var id: String { routine.id }
    let routine: Routine
    let judgeTotals: [(judge: String, total: Double)]
    let total: Double
    let maxScore: Double
}

struct EventSummary: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let slug: String
    let name: String
    let sourceName: String
    let isActive: Bool
}

enum SyncStatus: Equatable, Sendable {
    case localOnly
    case connecting
    case online
    case syncing
    case pending
    case offline(String)

    var title: String {
        switch self {
        case .localOnly: "Local"
        case .connecting: "Conectando"
        case .online: "Online"
        case .syncing: "Sincronizando"
        case .pending: "Pendiente"
        case .offline: "Offline"
        }
    }

    var systemImage: String {
        switch self {
        case .localOnly: "ipad"
        case .connecting: "arrow.triangle.2.circlepath"
        case .online: "checkmark.icloud"
        case .syncing: "arrow.triangle.2.circlepath.icloud"
        case .pending: "icloud.and.arrow.up"
        case .offline: "icloud.slash"
        }
    }
}

extension String {
    var normalizedKey: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
    }

    var stableRemoteID: String {
        let folded = folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
        let allowed = folded.map { character -> Character in
            character.isLetter || character.isNumber ? character : "-"
        }
        let compact = String(allowed)
            .split(separator: "-")
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return compact.isEmpty ? "sin-dato" : compact
    }
}
