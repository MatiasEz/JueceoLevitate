import Foundation

struct AppData: Codable, Sendable {
    var sourceName: String
    var blocks: [DanceBlock]
    var routines: [Routine]
    var templates: [JudgingTemplate]
    var judges: [String]
    var judgeProfiles: [JudgeProfile]?
}

enum UserRole: String, Codable, Sendable {
    case judge
    case admin
}

enum FavoriteCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case costume
    case choreography
    case music

    var id: String { rawValue }

    var title: String {
        switch self {
        case .costume: "Vestuario favorito"
        case .choreography: "Coreografía favorita"
        case .music: "Música favorita"
        }
    }

    var systemImage: String {
        switch self {
        case .costume: "tshirt.fill"
        case .choreography: "figure.dance"
        case .music: "music.note"
        }
    }
}

struct JudgeProfile: Codable, Identifiable, Hashable, Sendable {
    var id: String { judgeID }
    let judgeID: String
    let name: String
    let role: UserRole
}

struct DanceBlock: Codable, Identifiable, Sendable {
    var id: String { blockID ?? name.stableRemoteID }
    let blockID: String?
    let name: String
    let title: String
    let sortOrder: Int?
    let isActive: Bool?
    let routines: [Routine]
}

struct Routine: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let blockID: String?
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
    let judgePenalties: [(judge: String, value: Double)]
    let total: Double
    let penalty: Double
    let maxScore: Double
}

extension RoutineResult {
    var aggregateTotal: Double {
        judgeTotals.reduce(0) { $0 + $1.total }
    }
}

struct FavoriteSelectionSummary: Identifiable, Hashable, Sendable {
    let id: String
    let category: FavoriteCategory
    let judge: String
    let blockName: String
    let routine: Routine
}

struct FavoriteRankingBlock: Identifiable, Hashable, Sendable {
    var id: String { blockName.normalizedKey }
    let blockName: String
    let categories: [FavoriteCategoryRanking]

    var totalVotes: Int {
        categories.reduce(0) { $0 + $1.totalVotes }
    }
}

struct FavoriteCategoryRanking: Identifiable, Hashable, Sendable {
    var id: String { category.rawValue }
    let category: FavoriteCategory
    let items: [FavoriteRankingItem]

    var totalVotes: Int {
        items.reduce(0) { $0 + $1.votes }
    }
}

struct FavoriteRankingItem: Identifiable, Hashable, Sendable {
    let id: String
    let rank: Int
    let category: FavoriteCategory
    let blockName: String
    let routine: Routine
    let votes: Int
    let judges: [String]
}

struct EventSummary: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let slug: String
    let name: String
    let sourceName: String
    let isActive: Bool
    let eventType: String?
}

struct ExcelImportSummary: Sendable {
    let fileName: String
    let eventName: String
    let eventSlug: String
    let fileSize: Int
}

enum ExcelImportError: LocalizedError {
    case missingRemoteConfiguration
    case invalidFile
    case fileTooLarge(maxMegabytes: Int)

    var errorDescription: String? {
        switch self {
        case .missingRemoteConfiguration:
            "Supabase no está configurado."
        case .invalidFile:
            "No se pudo leer el Excel seleccionado."
        case let .fileTooLarge(maxMegabytes):
            "El archivo supera el máximo de \(maxMegabytes) MB."
        }
    }
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

    var isBackendLoading: Bool {
        switch self {
        case .connecting:
            true
        case .localOnly, .online, .syncing, .pending, .offline:
            false
        }
    }
}

enum DriveExportStatus: Equatable, Sendable {
    case idle
    case exporting
    case completed(Int)
    case failed(String)

    var title: String {
        switch self {
        case .idle:
            "Drive listo"
        case .exporting:
            "Exportando a Drive"
        case let .completed(count):
            "\(count) PDFs en Drive"
        case .failed:
            "Error en Drive"
        }
    }

    var systemImage: String {
        switch self {
        case .idle:
            "externaldrive"
        case .exporting:
            "arrow.triangle.2.circlepath"
        case .completed:
            "checkmark.icloud"
        case .failed:
            "exclamationmark.icloud"
        }
    }

    var isExporting: Bool {
        if case .exporting = self {
            return true
        }
        return false
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
