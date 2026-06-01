import Foundation

public struct AppData: Codable, Sendable {
    public var sourceName: String
    public var blocks: [DanceBlock]
    public var routines: [Routine]
    public var templates: [JudgingTemplate]
    public var judges: [String]
    public var judgeProfiles: [JudgeProfile]?

    public init(
        sourceName: String,
        blocks: [DanceBlock],
        routines: [Routine],
        templates: [JudgingTemplate],
        judges: [String],
        judgeProfiles: [JudgeProfile]? = nil
    ) {
        self.sourceName = sourceName
        self.blocks = blocks
        self.routines = routines
        self.templates = templates
        self.judges = judges
        self.judgeProfiles = judgeProfiles
    }
}

public enum OperationNoticeKind: Equatable {
    case success
    case failure
}

public struct OperationNotice: Identifiable, Equatable {
    public let id = UUID()
    public let kind: OperationNoticeKind
    public let title: String
    public let message: String

    public init(kind: OperationNoticeKind, title: String, message: String) {
        self.kind = kind
        self.title = title
        self.message = message
    }
}

public enum UserRole: String, Codable, Sendable {
    case judge
    case admin
}

public enum CompetitionPlacement: Equatable, Sendable {
    case position(Int)
    case participation

    public var order: Int {
        switch self {
        case let .position(value):
            value
        case .participation:
            4
        }
    }

    public var shortLabel: String {
        switch self {
        case let .position(value):
            "\(value)°"
        case .participation:
            "PART."
        }
    }

    public var tableLabel: String {
        switch self {
        case let .position(value):
            "\(value)°"
        case .participation:
            "PARTICIPACIÓN"
        }
    }

    public var isFirstPlace: Bool {
        self == .position(1)
    }

    public var isParticipation: Bool {
        self == .participation
    }

    public static func solo(for score: Double) -> CompetitionPlacement {
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

public enum FavoriteCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case costume
    case choreography
    case music

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .costume: "Vestuario favorito"
        case .choreography: "Coreografía favorita"
        case .music: "Música favorita"
        }
    }

    public var systemImage: String {
        switch self {
        case .costume: "tshirt.fill"
        case .choreography: "figure.dance"
        case .music: "music.note"
        }
    }
}

public enum SpecialAwardCategory: String, CaseIterable, Identifiable, Codable, Sendable, Hashable {
    case bestCostume = "best_costume"
    case bestMusic = "best_music"
    case bestChoreographicIdea = "best_choreographic_idea"
    case bestPorra = "best_porra"

    public static var routineBackedCases: [SpecialAwardCategory] {
        allCases.filter { !$0.isManualEntry }
    }

    public static var manualEntryCases: [SpecialAwardCategory] {
        allCases.filter(\.isManualEntry)
    }

    public var id: String { rawValue }

    public var isManualEntry: Bool {
        true
    }

    public var title: String {
        switch self {
        case .bestCostume: "Mejor vestuario"
        case .bestMusic: "Mejor música"
        case .bestChoreographicIdea: "Mejor idea coreográfica"
        case .bestPorra: "Mejor porra"
        }
    }

    public var systemImage: String {
        switch self {
        case .bestCostume: "tshirt.fill"
        case .bestMusic: "music.note"
        case .bestChoreographicIdea: "sparkles"
        case .bestPorra: "megaphone.fill"
        }
    }
}

public struct JudgeProfile: Codable, Identifiable, Hashable, Sendable {
    public var id: String { judgeID }
    public let judgeID: String
    public let name: String
    public let role: UserRole
    public let heroImageName: String?

    public init(judgeID: String, name: String, role: UserRole, heroImageName: String? = nil) {
        self.judgeID = judgeID
        self.name = name
        self.role = role
        self.heroImageName = heroImageName
    }
}

public struct DanceBlock: Codable, Identifiable, Sendable {
    public var id: String { blockID ?? name.stableRemoteID }
    public let blockID: String?
    public let name: String
    public let title: String
    public let sortOrder: Int?
    public let isActive: Bool?
    public let routines: [Routine]

    public init(blockID: String?, name: String, title: String, sortOrder: Int?, isActive: Bool?, routines: [Routine]) {
        self.blockID = blockID
        self.name = name
        self.title = title
        self.sortOrder = sortOrder
        self.isActive = isActive
        self.routines = routines
    }
}

public struct Routine: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let blockID: String?
    public let block: String
    public let name: String
    public let academy: String
    public let division: String
    public let genre: String
    public let level: String
    public let category: String
    public let choreographer: String
    public let participant: String?
    public let state: String
    public let time: String
    public let duration: String

    public init(
        id: String,
        blockID: String?,
        block: String,
        name: String,
        academy: String,
        division: String,
        genre: String,
        level: String,
        category: String,
        choreographer: String,
        participant: String?,
        state: String,
        time: String,
        duration: String
    ) {
        self.id = id
        self.blockID = blockID
        self.block = block
        self.name = name
        self.academy = academy
        self.division = division
        self.genre = genre
        self.level = level
        self.category = category
        self.choreographer = choreographer
        self.participant = participant
        self.state = state
        self.time = time
        self.duration = duration
    }
}

public extension Routine {
    var levelTagText: String? {
        let trimmed = level.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "-", trimmed.normalizedKey != "SIN NIVEL" else { return nil }
        return trimmed
    }
}

public enum RoutineMetadataField: String, CaseIterable, Identifiable, Sendable {
    case division
    case level
    case category
    case genre

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .division: "División"
        case .level: "Nivel"
        case .category: "Categoría"
        case .genre: "Género"
        }
    }

    public var systemImage: String {
        switch self {
        case .division: "person.2.fill"
        case .level: "slider.horizontal.3"
        case .category: "square.grid.2x2.fill"
        case .genre: "figure.dance"
        }
    }

    public func value(in routine: Routine) -> String {
        switch self {
        case .division: routine.division
        case .level: routine.level
        case .category: routine.category
        case .genre: routine.genre
        }
    }
}

public struct JudgingTemplate: Codable, Identifiable, Hashable, Sendable {
    public var id: String { genre.normalizedKey }
    public let genre: String
    public let title: String
    public let maxScore: Double
    public let criteria: [Criterion]

    public init(genre: String, title: String, maxScore: Double, criteria: [Criterion]) {
        self.genre = genre
        self.title = title
        self.maxScore = maxScore
        self.criteria = criteria
    }
}

public struct Criterion: Codable, Identifiable, Hashable, Sendable {
    public let id: Int
    public let section: String
    public let label: String
    public let maxScore: Double

    public init(id: Int, section: String, label: String, maxScore: Double) {
        self.id = id
        self.section = section
        self.label = label
        self.maxScore = maxScore
    }
}

public struct RoutineResult: Identifiable, Sendable {
    public var id: String { routine.id }
    public let routine: Routine
    public let judgeTotals: [(judge: String, total: Double)]
    public let judgePenalties: [(judge: String, value: Double)]
    public let total: Double
    public let penalty: Double
    public let maxScore: Double

    public init(
        routine: Routine,
        judgeTotals: [(judge: String, total: Double)],
        judgePenalties: [(judge: String, value: Double)],
        total: Double,
        penalty: Double,
        maxScore: Double
    ) {
        self.routine = routine
        self.judgeTotals = judgeTotals
        self.judgePenalties = judgePenalties
        self.total = total
        self.penalty = penalty
        self.maxScore = maxScore
    }
}

public extension RoutineResult {
    var aggregateTotal: Double {
        judgeTotals.reduce(0) { $0 + $1.total }
    }
}

public struct FavoriteSelectionSummary: Identifiable, Hashable, Sendable {
    public let id: String
    public let category: FavoriteCategory
    public let judge: String
    public let blockName: String
    public let routine: Routine

    public init(id: String, category: FavoriteCategory, judge: String, blockName: String, routine: Routine) {
        self.id = id
        self.category = category
        self.judge = judge
        self.blockName = blockName
        self.routine = routine
    }
}

public struct FavoriteRankingBlock: Identifiable, Hashable, Sendable {
    public var id: String { blockName.normalizedKey }
    public let blockName: String
    public let categories: [FavoriteCategoryRanking]

    public init(blockName: String, categories: [FavoriteCategoryRanking]) {
        self.blockName = blockName
        self.categories = categories
    }

    public var totalVotes: Int {
        categories.reduce(0) { $0 + $1.totalVotes }
    }
}

public struct FavoriteCategoryRanking: Identifiable, Hashable, Sendable {
    public var id: String { category.rawValue }
    public let category: FavoriteCategory
    public let items: [FavoriteRankingItem]

    public init(category: FavoriteCategory, items: [FavoriteRankingItem]) {
        self.category = category
        self.items = items
    }

    public var totalVotes: Int {
        items.reduce(0) { $0 + $1.votes }
    }
}

public struct FavoriteRankingItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let rank: Int
    public let category: FavoriteCategory
    public let blockName: String
    public let routine: Routine
    public let votes: Int
    public let judges: [String]

    public init(id: String, rank: Int, category: FavoriteCategory, blockName: String, routine: Routine, votes: Int, judges: [String]) {
        self.id = id
        self.rank = rank
        self.category = category
        self.blockName = blockName
        self.routine = routine
        self.votes = votes
        self.judges = judges
    }
}

public struct SpecialAwardSummary: Identifiable, Hashable, Sendable {
    public let category: SpecialAwardCategory
    public let blockName: String
    public let routine: Routine?
    public let manualValue: String?

    public init(category: SpecialAwardCategory, blockName: String, routine: Routine?, manualValue: String?) {
        self.category = category
        self.blockName = blockName
        self.routine = routine
        self.manualValue = manualValue
    }

    public var id: String {
        "\(blockName.normalizedKey)::\(category.rawValue)"
    }

    public var displayValue: String {
        if let manualValue = manualValue?.trimmingCharacters(in: .whitespacesAndNewlines), !manualValue.isEmpty {
            return manualValue
        }
        if let routine {
            return "#\(routine.id) \(routine.name)"
        }
        return "Sin asignar"
    }

    public var isAssigned: Bool {
        if routine != nil { return true }
        return !(manualValue?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
}

public enum JudgeActivityState: String, Codable, Sendable {
    case home
    case viewingSheet = "viewing_sheet"
    case leftSheet = "left_sheet"
}

public struct JudgeActivitySummary: Identifiable, Hashable, Sendable {
    public let eventID: String
    public let judgeID: String
    public let judgeName: String
    public let deviceID: String
    public let state: JudgeActivityState
    public let blockID: String?
    public let blockName: String?
    public let routine: Routine?
    public let routineID: String?
    public let platform: String
    public let updatedAt: Date

    public init(
        eventID: String,
        judgeID: String,
        judgeName: String,
        deviceID: String,
        state: JudgeActivityState,
        blockID: String?,
        blockName: String?,
        routine: Routine?,
        routineID: String?,
        platform: String,
        updatedAt: Date
    ) {
        self.eventID = eventID
        self.judgeID = judgeID
        self.judgeName = judgeName
        self.deviceID = deviceID
        self.state = state
        self.blockID = blockID
        self.blockName = blockName
        self.routine = routine
        self.routineID = routineID
        self.platform = platform
        self.updatedAt = updatedAt
    }

    public var id: String {
        "\(eventID)::\(judgeID)::\(deviceID)"
    }

    public func isInactive(now: Date = Date(), threshold: TimeInterval = 600) -> Bool {
        now.timeIntervalSince(updatedAt) > threshold
    }

    public var statusTitle: String {
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

    public var detail: String {
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

public struct EventSummary: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let slug: String
    public let name: String
    public let sourceName: String
    public let isActive: Bool
    public let eventType: String?

    public init(id: String, slug: String, name: String, sourceName: String, isActive: Bool, eventType: String?) {
        self.id = id
        self.slug = slug
        self.name = name
        self.sourceName = sourceName
        self.isActive = isActive
        self.eventType = eventType
    }
}

public struct ExcelImportSummary: Sendable {
    public let fileName: String
    public let eventName: String
    public let eventSlug: String
    public let fileSize: Int
    public let eventID: String?
    public let routineCount: Int?

    public init(fileName: String, eventName: String, eventSlug: String, fileSize: Int, eventID: String?, routineCount: Int?) {
        self.fileName = fileName
        self.eventName = eventName
        self.eventSlug = eventSlug
        self.fileSize = fileSize
        self.eventID = eventID
        self.routineCount = routineCount
    }
}

public enum ExcelImportError: LocalizedError {
    case missingRemoteConfiguration
    case missingImportSecret
    case notAllowed
    case invalidFile
    case fileTooLarge(maxMegabytes: Int)

    public var errorDescription: String? {
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

public enum EventDeletionError: LocalizedError {
    case missingRemoteConfiguration
    case notAllowed

    public var errorDescription: String? {
        switch self {
        case .missingRemoteConfiguration:
            "Supabase no está configurado."
        case .notAllowed:
            "Solo un admin puede borrar programas."
        }
    }
}

public enum RoutineDeletionError: LocalizedError {
    case missingRemoteConfiguration
    case missingSelectedEvent
    case missingImportSecret
    case notAllowed

    public var errorDescription: String? {
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

public enum RoutineUpdateError: LocalizedError {
    case missingRemoteConfiguration
    case missingSelectedEvent
    case notAllowed
    case updateNotApplied(String)

    public var errorDescription: String? {
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

public enum SpecialAwardSaveError: LocalizedError {
    case missingRemoteConfiguration
    case missingSelectedEvent
    case missingSelectedBlock
    case notAllowed

    public var errorDescription: String? {
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

public enum JudgeDeletionError: LocalizedError {
    case missingSelectedEvent
    case notAllowed

    public var errorDescription: String? {
        switch self {
        case .missingSelectedEvent:
            "Elegí un programa online antes de borrar un juez."
        case .notAllowed:
            "Solo un admin puede borrar jueces."
        }
    }
}

public enum JudgeSaveError: LocalizedError {
    case missingSelectedEvent
    case notAllowed

    public var errorDescription: String? {
        switch self {
        case .missingSelectedEvent:
            "Elegí un programa online antes de agregar un juez."
        case .notAllowed:
            "Solo un admin puede agregar jueces."
        }
    }
}

public enum SyncStatus: Equatable, Sendable {
    case localOnly
    case connecting
    case online
    case syncing
    case pending
    case offline(String)

    public var title: String {
        switch self {
        case .localOnly: "Local"
        case .connecting: "Conectando"
        case .online: "Online"
        case .syncing: "Sincronizando"
        case .pending: "Pendiente"
        case .offline: "Offline"
        }
    }

    public var systemImage: String {
        switch self {
        case .localOnly: "ipad"
        case .connecting: "arrow.triangle.2.circlepath"
        case .online: "checkmark.icloud"
        case .syncing: "arrow.triangle.2.circlepath.icloud"
        case .pending: "icloud.and.arrow.up"
        case .offline: "icloud.slash"
        }
    }

    public var isBackendLoading: Bool {
        switch self {
        case .connecting:
            true
        case .localOnly, .online, .syncing, .pending, .offline:
            false
        }
    }
}

public enum DriveExportStatus: Equatable, Sendable {
    case idle
    case exporting
    case completed(Int)
    case failed(String)

    public var title: String {
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

    public var systemImage: String {
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

    public var isExporting: Bool {
        if case .exporting = self {
            return true
        }
        return false
    }
}

public extension String {
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
