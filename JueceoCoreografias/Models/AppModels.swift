import Foundation

struct AppData: Codable, Sendable {
    var sourceName: String
    var blocks: [DanceBlock]
    var routines: [Routine]
    var templates: [JudgingTemplate]
    var judges: [String]
    var judgeProfiles: [JudgeProfile]?
}

enum OperationNoticeKind: Equatable {
    case success
    case failure
}

struct OperationNotice: Identifiable, Equatable {
    let id = UUID()
    let kind: OperationNoticeKind
    let title: String
    let message: String
}

enum UserRole: String, Codable, Sendable {
    case judge
    case admin
}

enum CompetitionPlacement: Equatable, Sendable {
    case position(Int)
    case participation

    var order: Int {
        switch self {
        case let .position(value):
            value
        case .participation:
            4
        }
    }

    var shortLabel: String {
        switch self {
        case let .position(value):
            "\(value)°"
        case .participation:
            "PART."
        }
    }

    var tableLabel: String {
        switch self {
        case let .position(value):
            "\(value)°"
        case .participation:
            "PARTICIPACIÓN"
        }
    }

    var isFirstPlace: Bool {
        self == .position(1)
    }

    var isParticipation: Bool {
        self == .participation
    }

    static func solo(for score: Double) -> CompetitionPlacement {
        if score >= 181 {
            return .position(1)
        }
        if score >= 161 {
            return .position(2)
        }
        if score >= 141 {
            return .position(3)
        }
        return .participation
    }
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

enum SpecialAwardCategory: String, CaseIterable, Identifiable, Codable, Sendable, Hashable {
    case bestCostume = "best_costume"
    case bestMusic = "best_music"
    case bestChoreographicIdea = "best_choreographic_idea"
    case bestPorra = "best_porra"

    static var routineBackedCases: [SpecialAwardCategory] {
        allCases.filter { !$0.isManualEntry }
    }

    static var manualEntryCases: [SpecialAwardCategory] {
        allCases.filter(\.isManualEntry)
    }

    var id: String { rawValue }

    var isManualEntry: Bool {
        true
    }

    var title: String {
        switch self {
        case .bestCostume: "Mejor vestuario"
        case .bestMusic: "Mejor música"
        case .bestChoreographicIdea: "Mejor idea coreográfica"
        case .bestPorra: "Mejor porra"
        }
    }

    var systemImage: String {
        switch self {
        case .bestCostume: "tshirt.fill"
        case .bestMusic: "music.note"
        case .bestChoreographicIdea: "sparkles"
        case .bestPorra: "megaphone.fill"
        }
    }
}

struct JudgeProfile: Codable, Identifiable, Hashable, Sendable {
    var id: String { judgeID }
    let judgeID: String
    let name: String
    let role: UserRole
    let heroImageName: String?

    init(judgeID: String, name: String, role: UserRole, heroImageName: String? = nil) {
        self.judgeID = judgeID
        self.name = name
        self.role = role
        self.heroImageName = heroImageName
    }
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
    let participant: String?
    let state: String
    let time: String
    let duration: String
}

extension Routine {
    var levelTagText: String? {
        let trimmed = level.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "-", trimmed.normalizedKey != "SIN NIVEL" else { return nil }
        return trimmed
    }
}

enum RoutineMetadataField: String, CaseIterable, Identifiable, Sendable {
    case division
    case level
    case category
    case genre

    var id: String { rawValue }

    var title: String {
        switch self {
        case .division: "División"
        case .level: "Nivel"
        case .category: "Categoría"
        case .genre: "Género"
        }
    }

    var systemImage: String {
        switch self {
        case .division: "person.2.fill"
        case .level: "slider.horizontal.3"
        case .category: "square.grid.2x2.fill"
        case .genre: "figure.dance"
        }
    }

    func value(in routine: Routine) -> String {
        switch self {
        case .division: routine.division
        case .level: routine.level
        case .category: routine.category
        case .genre: routine.genre
        }
    }
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

struct SpecialAwardSummary: Identifiable, Hashable, Sendable {
    let category: SpecialAwardCategory
    let blockName: String
    let routine: Routine?
    let manualValue: String?

    var id: String {
        "\(blockName.normalizedKey)::\(category.rawValue)"
    }

    var displayValue: String {
        if let manualValue = manualValue?.trimmingCharacters(in: .whitespacesAndNewlines), !manualValue.isEmpty {
            return manualValue
        }
        if let routine {
            return "#\(routine.id) \(routine.name)"
        }
        return "Sin asignar"
    }

    var isAssigned: Bool {
        if routine != nil { return true }
        return !(manualValue?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
}

enum JudgeActivityState: String, Codable, Sendable {
    case home
    case viewingSheet = "viewing_sheet"
    case leftSheet = "left_sheet"
}

struct JudgeActivitySummary: Identifiable, Hashable, Sendable {
    let eventID: String
    let judgeID: String
    let judgeName: String
    let deviceID: String
    let state: JudgeActivityState
    let blockID: String?
    let blockName: String?
    let routine: Routine?
    let routineID: String?
    let platform: String
    let updatedAt: Date

    var id: String {
        "\(eventID)::\(judgeID)::\(deviceID)"
    }

    func isInactive(now: Date = Date(), threshold: TimeInterval = 600) -> Bool {
        now.timeIntervalSince(updatedAt) > threshold
    }

    var statusTitle: String {
        switch state {
        case .home:
            "Está en Home"
        case .viewingSheet:
            if let routine {
                "Está en hoja #\(routine.id) \(routine.name)"
            } else if let routineID, !routineID.isEmpty {
                "Está en hoja #\(routineID)"
            } else {
                "Está en una hoja"
            }
        case .leftSheet:
            if let routine {
                "Salió de hoja #\(routine.id) \(routine.name)"
            } else if let routineID, !routineID.isEmpty {
                "Salió de hoja #\(routineID)"
            } else {
                "Salió de una hoja"
            }
        }
    }

    var detail: String {
        let platformLabel = platform.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanBlock = blockName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanAcademy = routine?.academy.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = [
            cleanBlock?.isEmpty == false ? cleanBlock : nil,
            cleanAcademy?.isEmpty == false ? cleanAcademy : nil,
            platformLabel.isEmpty ? nil : platformLabel.capitalized
        ].compactMap { $0 }
        return parts.isEmpty ? "Sin detalle" : parts.joined(separator: " · ")
    }
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
    let eventID: String?
    let routineCount: Int?
}

enum ExcelImportError: LocalizedError {
    case missingRemoteConfiguration
    case missingImportSecret
    case notAllowed
    case invalidFile
    case fileTooLarge(maxMegabytes: Int)

    var errorDescription: String? {
        switch self {
        case .missingRemoteConfiguration:
            "Supabase no está configurado."
        case .missingImportSecret:
            "Falta la clave de importación."
        case .notAllowed:
            "Solo un admin puede importar Excel."
        case .invalidFile:
            "No se pudo leer el Excel seleccionado."
        case let .fileTooLarge(maxMegabytes):
            "El archivo supera el máximo de \(maxMegabytes) MB."
        }
    }
}

enum EventDeletionError: LocalizedError {
    case missingRemoteConfiguration
    case notAllowed

    var errorDescription: String? {
        switch self {
        case .missingRemoteConfiguration:
            "Supabase no está configurado."
        case .notAllowed:
            "Solo un admin puede borrar programas."
        }
    }
}

enum RoutineDeletionError: LocalizedError {
    case missingRemoteConfiguration
    case missingSelectedEvent
    case missingImportSecret
    case notAllowed

    var errorDescription: String? {
        switch self {
        case .missingRemoteConfiguration:
            "Supabase no está configurado."
        case .missingSelectedEvent:
            "Elegí un programa online antes de borrar una coreografía."
        case .missingImportSecret:
            "Ingresá la clave de importación para borrar la coreografía."
        case .notAllowed:
            "Solo un admin puede borrar coreografías."
        }
    }
}

enum RoutineUpdateError: LocalizedError {
    case missingRemoteConfiguration
    case missingSelectedEvent
    case notAllowed
    case updateNotApplied(String)

    var errorDescription: String? {
        switch self {
        case .missingRemoteConfiguration:
            "Supabase no está configurado."
        case .missingSelectedEvent:
            "Elegí un programa online antes de editar una coreografía."
        case .notAllowed:
            "Solo un admin puede editar coreografías."
        case .updateNotApplied(let field):
            "No se pudo aplicar el cambio de \(field). Puede que falte desplegar la función update-routine en Supabase."
        }
    }
}

enum SpecialAwardSaveError: LocalizedError {
    case missingRemoteConfiguration
    case missingSelectedEvent
    case missingSelectedBlock
    case notAllowed

    var errorDescription: String? {
        switch self {
        case .missingRemoteConfiguration:
            "Supabase no está configurado."
        case .missingSelectedEvent:
            "Elegí un programa online antes de guardar premios especiales."
        case .missingSelectedBlock:
            "Elegí un bloque antes de guardar premios especiales."
        case .notAllowed:
            "Solo un admin puede editar premios especiales."
        }
    }
}

enum JudgeDeletionError: LocalizedError {
    case missingSelectedEvent
    case notAllowed

    var errorDescription: String? {
        switch self {
        case .missingSelectedEvent:
            "Elegí un programa online antes de borrar un juez."
        case .notAllowed:
            "Solo un admin puede borrar jueces."
        }
    }
}

enum JudgeSaveError: LocalizedError {
    case missingSelectedEvent
    case notAllowed

    var errorDescription: String? {
        switch self {
        case .missingSelectedEvent:
            "Elegí un programa online antes de agregar un juez."
        case .notAllowed:
            "Solo un admin puede agregar jueces."
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
