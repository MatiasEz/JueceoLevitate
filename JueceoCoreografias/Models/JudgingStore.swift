import Foundation
import SwiftUI

private enum DriveExportError: LocalizedError {
    case pdfGenerationFailed
    case routineBlockNotFound

    var errorDescription: String? {
        switch self {
        case .pdfGenerationFailed:
            "No se pudo generar el PDF de calificaciones."
        case .routineBlockNotFound:
            "No se pudo ubicar el bloque de esta coreografía."
        }
    }
}

private enum DataRefreshError: LocalizedError {
    case missingRemoteConfiguration
    case noEvents

    var errorDescription: String? {
        switch self {
        case .missingRemoteConfiguration:
            "Supabase no está configurado."
        case .noEvents:
            "No hay programas cargados en Supabase."
        }
    }
}

@MainActor
final class JudgingStore: ObservableObject {
    @Published private(set) var appData: AppData
    @Published private(set) var availableEvents: [EventSummary] = []
    @Published private(set) var selectedEventID: String?
    @Published private(set) var selectedBlockID: String?
    @Published private(set) var syncStatus: SyncStatus = .localOnly
    @Published private(set) var syncMessage: String?
    @Published var selectedRoutineID: String
    @Published var selectedJudge: String {
        didSet { persistSelectedJudge() }
    }
    @Published private(set) var adminScoringJudge: String?
    @Published var scores: [String: Double] = [:]
    @Published var feedback: [String: String] = [:]
    @Published var penalties: [String: Double] = [:]
    @Published var favoriteSelections: [String: String] = [:]
    @Published var lastPDFURL: URL?
    @Published private(set) var driveExportStatus: DriveExportStatus = .idle
    @Published private(set) var driveExportMessage: String?
    @Published private(set) var lastDriveExportSummary: GoogleDriveExportSummary?
    @Published private(set) var operationNotice: OperationNotice?

    private let scoresKey = "jueceo.scores.pending.v2"
    private let feedbackKey = "jueceo.feedback.pending.v2"
    private let penaltiesKey = "jueceo.penalties.pending.v2"
    private let favoriteSelectionsKey = "jueceo.favoriteSelections.pending.v2"
    private let legacyScoresStorageKey = "jueceo.scores.v1"
    private let legacyFeedbackStorageKey = "jueceo.feedback.v1"
    private let legacyPenaltiesStorageKey = "jueceo.penalties.v1"
    private let legacyFavoriteSelectionsStorageKey = "jueceo.favoriteSelections.v1"
    private let pendingScoreKeysKey = "jueceo.pendingScoreKeys.v1"
    private let pendingFeedbackKeysKey = "jueceo.pendingFeedbackKeys.v1"
    private let pendingPenaltyKeysKey = "jueceo.pendingPenaltyKeys.v1"
    private let pendingFavoriteKeysKey = "jueceo.pendingFavoriteKeys.v1"
    private let selectedEventKey = "jueceo.selectedEventID.v1"
    private let selectedBlockKey = "jueceo.selectedBlockID.v1"
    private let selectedJudgeKey = "jueceo.selectedJudge.v1"
    private let deviceIDKey = "jueceo.deviceID.v1"
    private var pendingScoreKeys: Set<String> = []
    private var pendingFeedbackKeys: Set<String> = []
    private var pendingPenaltyKeys: Set<String> = []
    private var pendingFavoriteKeys: Set<String> = []
    private let remoteRepository: RemoteJudgingRepository?
    private var didStartRemote = false
    private var operationNoticeTask: Task<Void, Never>?

    init() {
        let initStart = LoadDiagnostics.start()
        let data = Self.loadBundledData()
        let repository = SupabaseConfig.load().map { RemoteJudgingRepository(config: $0) }
        remoteRepository = repository
        appData = data
        selectedRoutineID = data.routines.first?.id ?? ""
        let savedJudge = UserDefaults.standard.string(forKey: selectedJudgeKey)
        selectedJudge = savedJudge.flatMap { data.judges.contains($0) ? $0 : nil }
            ?? data.judges.first
            ?? "JUEZ"
        pendingScoreKeys = Self.loadSet(pendingScoreKeysKey)
        pendingFeedbackKeys = Self.loadSet(pendingFeedbackKeysKey)
        pendingPenaltyKeys = Self.loadSet(pendingPenaltyKeysKey)
        pendingFavoriteKeys = Self.loadSet(pendingFavoriteKeysKey)
        if repository == nil {
            scores = Self.loadDictionary(scoresKey) ?? Self.loadDictionary(legacyScoresStorageKey) ?? [:]
            feedback = Self.loadDictionary(feedbackKey) ?? Self.loadDictionary(legacyFeedbackStorageKey) ?? [:]
            penalties = Self.loadDictionary(penaltiesKey) ?? Self.loadDictionary(legacyPenaltiesStorageKey) ?? [:]
            favoriteSelections = Self.loadDictionary(favoriteSelectionsKey) ?? Self.loadDictionary(legacyFavoriteSelectionsStorageKey) ?? [:]
        } else {
            Self.removeStoredValue(legacyScoresStorageKey)
            Self.removeStoredValue(legacyFeedbackStorageKey)
            Self.removeStoredValue(legacyPenaltiesStorageKey)
            Self.removeStoredValue(legacyFavoriteSelectionsStorageKey)
            scores = Self.loadDictionary(scoresKey) ?? [:]
            feedback = Self.loadDictionary(feedbackKey) ?? [:]
            penalties = Self.loadDictionary(penaltiesKey) ?? [:]
            favoriteSelections = Self.loadDictionary(favoriteSelectionsKey) ?? [:]
            scores = scores.filter { pendingScoreKeys.contains($0.key) }
            feedback = feedback.filter { pendingFeedbackKeys.contains($0.key) }
            penalties = penalties.filter { pendingPenaltyKeys.contains($0.key) }
            favoriteSelections = favoriteSelections.filter { pendingFavoriteKeys.contains($0.key) }
            persistLocalCaches()
        }
        selectedEventID = UserDefaults.standard.string(forKey: selectedEventKey)
        selectedBlockID = UserDefaults.standard.string(forKey: selectedBlockKey)
        if repository != nil {
            syncStatus = pendingSyncCount > 0 ? .pending : .connecting
        } else {
            syncStatus = .localOnly
        }
        LoadDiagnostics.log(
            "JudgingStore init routines=\(appData.routines.count) blocks=\(appData.blocks.count) judges=\(appData.judges.count) localScores=\(scores.count) localFeedback=\(feedback.count) localPenalties=\(penalties.count) localFavorites=\(favoriteSelections.count) pending=\(pendingSyncCount) remoteConfigured=\(remoteRepository != nil) elapsed=\(LoadDiagnostics.elapsed(since: initStart))"
        )
    }

    var routines: [Routine] { appData.routines }
    var judges: [String] { appData.judges }
    var orderedJudges: [String] {
        judges.sorted { lhs, rhs in
            let lhsIsAdmin = role(for: lhs) == .admin
            let rhsIsAdmin = role(for: rhs) == .admin
            if lhsIsAdmin != rhsIsAdmin {
                return !lhsIsAdmin
            }
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
    }
    var judgeProfiles: [JudgeProfile] {
        let profilesByID = Dictionary(uniqueKeysWithValues: (appData.judgeProfiles ?? []).map { ($0.judgeID, $0) })
        return appData.judges.map { judge in
            let judgeID = judge.stableRemoteID
            return profilesByID[judgeID] ?? JudgeProfile(
                judgeID: judgeID,
                name: judge,
                role: judgeID == "ati" ? .admin : .judge
            )
        }
    }
    var selectedRole: UserRole { role(for: selectedJudge) }
    var isAdmin: Bool { selectedRole == .admin }
    var scoringJudge: String {
        isAdmin ? (adminScoringJudge ?? selectedJudge) : selectedJudge
    }
    var isAdminEditingAsJudge: Bool {
        isAdmin && adminScoringJudge != nil && adminScoringJudge != selectedJudge
    }
    var editableJudges: [String] {
        judges.filter { role(for: $0) == .judge }
    }
    var orderedEditableJudges: [String] {
        orderedJudges.filter { role(for: $0) == .judge }
    }
    var deletableJudges: [String] {
        orderedJudges.filter(canDeleteJudge)
    }
    var blocks: [DanceBlock] { appData.blocks }
    var selectedBlock: DanceBlock? {
        if let selectedBlockID,
           let block = blocks.first(where: { $0.id == selectedBlockID || $0.name == selectedBlockID }) {
            return block
        }
        return blocks.first(where: { $0.isActive == true }) ?? blocks.first
    }
    var visibleRoutines: [Routine] {
        guard let selectedBlock else { return routines }
        let blockRoutineIDs = Set(selectedBlock.routines.map(\.id))
        let blockID = selectedBlock.id
        let visible = routines.filter { routine in
            blockRoutineIDs.contains(routine.id)
                || routine.blockID == blockID
                || routine.block == selectedBlock.name
        }
        if visible.isEmpty && selectedBlock.routines.isEmpty {
            return []
        }
        return visible.isEmpty ? routines : visible
    }
    var hasRemoteConfiguration: Bool { remoteRepository != nil }
    var hasGoogleDriveConfiguration: Bool { GoogleDriveConfig.load() != nil }
    var defaultDriveRootFolderName: String {
        GoogleDriveConfig.load()?.rootFolderName ?? "FEEDBACK LEVITATE MX"
    }
    var pendingSyncCount: Int {
        pendingScoreKeys.count + pendingFeedbackKeys.count + pendingPenaltyKeys.count + pendingFavoriteKeys.count
    }
    var isLoadingBackendData: Bool { hasRemoteConfiguration && syncStatus.isBackendLoading }
    var backendLoadingMessage: String {
        syncMessage ?? "Cargando informacion del backend..."
    }

    var selectedRoutine: Routine? {
        visibleRoutines.first { $0.id == selectedRoutineID }
            ?? visibleRoutines.first
            ?? routines.first
    }

    var favoriteSummaries: [FavoriteSelectionSummary] {
        let currentEventKey = selectedEventID ?? appData.sourceName.stableRemoteID
        let routinesByID = Dictionary(uniqueKeysWithValues: routines.map { ($0.id, $0) })
        return favoriteSelections.compactMap { key, routineID in
            guard
                let parsed = parseFavoriteKey(key),
                parsed.eventID == currentEventKey,
                let routine = routinesByID[routineID]
            else {
                return nil
            }

            return FavoriteSelectionSummary(
                id: key,
                category: parsed.category,
                judge: judgeName(forNormalizedKey: parsed.judgeKey) ?? parsed.judgeKey.uppercased(),
                blockName: blockName(for: parsed.blockID),
                routine: routine
            )
        }
        .sorted { lhs, rhs in
            let lhsBlockOrder = blockSortOrder(named: lhs.blockName)
            let rhsBlockOrder = blockSortOrder(named: rhs.blockName)
            if lhsBlockOrder != rhsBlockOrder {
                return lhsBlockOrder < rhsBlockOrder
            }
            let lhsCategoryOrder = FavoriteCategory.allCases.firstIndex(of: lhs.category) ?? Int.max
            let rhsCategoryOrder = FavoriteCategory.allCases.firstIndex(of: rhs.category) ?? Int.max
            if lhsCategoryOrder != rhsCategoryOrder {
                return lhsCategoryOrder < rhsCategoryOrder
            }
            if lhs.judge != rhs.judge {
                return lhs.judge.localizedStandardCompare(rhs.judge) == .orderedAscending
            }
            return (Int(lhs.routine.id) ?? Int.max) < (Int(rhs.routine.id) ?? Int.max)
        }
    }

    var favoriteRankingBlocks: [FavoriteRankingBlock] {
        Dictionary(grouping: favoriteSummaries, by: \.blockName)
            .map { blockName, blockFavorites in
                let categories = FavoriteCategory.allCases.map { category in
                    let categoryFavorites = blockFavorites.filter { $0.category == category }
                    let items = Dictionary(grouping: categoryFavorites, by: { $0.routine.id })
                        .compactMap { routineID, picks -> (routine: Routine, votes: Int, judges: [String])? in
                            guard let routine = picks.first?.routine else { return nil }
                            let judges = Array(Set(picks.map(\.judge)))
                                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
                            return (routine, judges.count, judges)
                        }
                        .sorted { lhs, rhs in
                            if lhs.votes == rhs.votes {
                                return routineOrder(lhs.routine, rhs.routine)
                            }
                            return lhs.votes > rhs.votes
                        }
                        .prefix(3)
                        .enumerated()
                        .map { index, item in
                            FavoriteRankingItem(
                                id: "\(blockName.normalizedKey)::\(category.rawValue)::\(item.routine.id)",
                                rank: index + 1,
                                category: category,
                                blockName: blockName,
                                routine: item.routine,
                                votes: item.votes,
                                judges: item.judges
                            )
                        }
                    return FavoriteCategoryRanking(category: category, items: items)
                }
                return FavoriteRankingBlock(blockName: blockName, categories: categories)
            }
            .filter { $0.totalVotes > 0 }
            .sorted {
                let lhsOrder = blockSortOrder(named: $0.blockName)
                let rhsOrder = blockSortOrder(named: $1.blockName)
                if lhsOrder == rhsOrder {
                    return $0.blockName.localizedStandardCompare($1.blockName) == .orderedAscending
                }
                return lhsOrder < rhsOrder
            }
    }

    func template(for routine: Routine) -> JudgingTemplate {
        appData.templates.first { $0.genre.normalizedKey == routine.genre.normalizedKey }
            ?? appData.templates.first
            ?? JudgingTemplate(genre: "General", title: "Hoja de jueceo", maxScore: 0, criteria: [])
    }

    @discardableResult
    func addJudge(_ name: String) async throws -> String? {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !cleanName.isEmpty, !appData.judges.contains(cleanName) else { return nil }
        let role: UserRole = cleanName.stableRemoteID == "ati" ? .admin : .judge

        if let remoteRepository {
            guard isAdmin else {
                throw JudgeSaveError.notAllowed
            }
            guard let eventID = selectedEventID else {
                throw JudgeSaveError.missingSelectedEvent
            }

            syncStatus = .syncing
            syncMessage = "Agregando juez \(cleanName)..."
            let response = try await remoteRepository.upsertJudge(
                eventID: eventID,
                judgeID: cleanName.stableRemoteID,
                name: cleanName,
                role: role
            )
            let bundle = try await remoteRepository.fetchEventBundle(eventID: eventID)
            applyRemoteBundle(bundle)
            await syncPending()
            syncStatus = pendingSyncCount > 0 ? .pending : .online
            let savedName = response.judgeName.isEmpty ? cleanName : response.judgeName
            syncMessage = "Juez \(savedName) agregado."
            selectJudge(savedName)
            return savedName
        }

        appData.judges.append(cleanName)
        appendOrUpdateJudgeProfile(name: cleanName, role: role)
        selectJudge(cleanName)
        return cleanName
    }

    func canDeleteJudge(_ judge: String) -> Bool {
        appData.judges.contains(judge) && role(for: judge) != .admin
    }

    func deleteJudge(_ judge: String) async throws {
        guard canDeleteJudge(judge) else { return }

        if let remoteRepository {
            guard isAdmin else {
                throw JudgeDeletionError.notAllowed
            }
            guard let eventID = selectedEventID else {
                throw JudgeDeletionError.missingSelectedEvent
            }

            syncStatus = .syncing
            syncMessage = "Borrando juez \(judge)..."
            let response: JudgeDeleteResponse
            do {
                response = try await remoteRepository.deleteJudge(
                    eventID: eventID,
                    judgeID: judge.stableRemoteID
                )
            } catch RemoteJudgingError.http(let status, let detail)
                where status == 404 && detail.localizedCaseInsensitiveContains("No se encontro el juez") {
                purgeLocalState(forJudge: judge)
                let bundle = try await remoteRepository.fetchEventBundle(eventID: eventID)
                applyRemoteBundle(bundle)
                await syncPending()
                syncStatus = pendingSyncCount > 0 ? .pending : .online
                syncMessage = "Juez \(judge) quitado localmente; no existía en Supabase."
                return
            }

            purgeLocalState(forJudge: judge)
            let bundle = try await remoteRepository.fetchEventBundle(eventID: eventID)
            applyRemoteBundle(bundle)
            await syncPending()
            syncStatus = pendingSyncCount > 0 ? .pending : .online
            let deletedName = response.judgeName.isEmpty ? judge : response.judgeName
            syncMessage = "Juez \(deletedName) borrado."
        } else {
            purgeLocalState(forJudge: judge)
        }
    }

    private func purgeLocalState(forJudge judge: String) {
        appData.judges.removeAll { $0 == judge }
        if var profiles = appData.judgeProfiles {
            profiles.removeAll {
                matchesJudgeKey($0.judgeID, judge: judge)
                    || $0.name.normalizedKey == judge.normalizedKey
            }
            appData.judgeProfiles = profiles
        }

        scores = scores.filter { key, _ in
            guard let parsed = parseScoreKey(key) else { return true }
            return !(isCurrentDataScope(parsed.eventID) && matchesJudgeKey(parsed.judgeKey, judge: judge))
        }
        feedback = feedback.filter { key, _ in
            guard let parsed = parseFeedbackKey(key) else { return true }
            return !(isCurrentDataScope(parsed.eventID) && matchesJudgeKey(parsed.judgeKey, judge: judge))
        }
        penalties = penalties.filter { key, _ in
            guard let parsed = parsePenaltyKey(key) else { return true }
            return !(isCurrentDataScope(parsed.eventID) && matchesJudgeKey(parsed.judgeKey, judge: judge))
        }
        favoriteSelections = favoriteSelections.filter { key, _ in
            guard let parsed = parseFavoriteKey(key) else { return true }
            return !(parsed.eventID == currentDataScopeKey && matchesJudgeKey(parsed.judgeKey, judge: judge))
        }

        pendingScoreKeys = pendingScoreKeys.filter { key in
            guard let parsed = parseScoreKey(key) else { return true }
            return !(isCurrentDataScope(parsed.eventID) && matchesJudgeKey(parsed.judgeKey, judge: judge))
        }
        pendingFeedbackKeys = pendingFeedbackKeys.filter { key in
            guard let parsed = parseFeedbackKey(key) else { return true }
            return !(isCurrentDataScope(parsed.eventID) && matchesJudgeKey(parsed.judgeKey, judge: judge))
        }
        pendingPenaltyKeys = pendingPenaltyKeys.filter { key in
            guard let parsed = parsePenaltyKey(key) else { return true }
            return !(isCurrentDataScope(parsed.eventID) && matchesJudgeKey(parsed.judgeKey, judge: judge))
        }
        pendingFavoriteKeys = pendingFavoriteKeys.filter { key in
            guard let parsed = parseFavoriteKey(key) else { return true }
            return !(parsed.eventID == currentDataScopeKey && matchesJudgeKey(parsed.judgeKey, judge: judge))
        }
        persistPendingScoreKeys()
        persistPendingFeedbackKeys()
        persistPendingPenaltyKeys()
        persistPendingFavoriteKeys()
        persistLocalCaches()

        if let adminScoringJudge, matchesJudgeKey(adminScoringJudge, judge: judge) {
            self.adminScoringJudge = nil
        }
        if matchesJudgeKey(selectedJudge, judge: judge) {
            selectedJudge = orderedJudges.first ?? "JUEZ"
        }
    }

    func selectJudge(_ judge: String) {
        guard appData.judges.contains(judge) else { return }
        selectedJudge = judge
        if role(for: judge) != .admin {
            adminScoringJudge = nil
        }
    }

    func beginAdminScoring(judge: String, routine: Routine) {
        guard isAdmin, appData.judges.contains(judge), role(for: judge) == .judge else { return }
        adminScoringJudge = judge
        selectedRoutineID = routine.id
        if let block = block(containing: routine) {
            selectedBlockID = block.id
            UserDefaults.standard.set(block.id, forKey: selectedBlockKey)
        }
    }

    func clearAdminScoringOverride() {
        adminScoringJudge = nil
    }

    func role(for judge: String) -> UserRole {
        let judgeID = judge.stableRemoteID
        if judgeID == "ati" {
            return .admin
        }
        return appData.judgeProfiles?.first { $0.judgeID == judgeID || $0.name.normalizedKey == judge.normalizedKey }?.role ?? .judge
    }

    func roleTitle(for judge: String) -> String {
        switch role(for: judge) {
        case .admin: "Admin"
        case .judge: "Juez"
        }
    }

    func canAccess(_ section: AppSection) -> Bool {
        isAdmin || !section.requiresAdmin
    }

    func showOperationSuccess(_ title: String, message: String) {
        showOperationNotice(kind: .success, title: title, message: message)
    }

    func showOperationFailure(_ title: String, message: String) {
        showOperationNotice(kind: .failure, title: title, message: message)
    }

    func dismissOperationNotice() {
        operationNoticeTask?.cancel()
        operationNoticeTask = nil
        operationNotice = nil
    }

    func selectBlock(_ block: DanceBlock) {
        selectedBlockID = block.id
        UserDefaults.standard.set(block.id, forKey: selectedBlockKey)
        let nextRoutine = block.routines.first
            ?? routines.first { $0.blockID == block.id || $0.block == block.name }
            ?? routines.first
        selectedRoutineID = nextRoutine?.id ?? ""
    }

    func scoreKey(routineID: String, judge: String, criterionID: Int) -> String {
        "\(currentDataScopeKey)::\(routineID)::\(judge.normalizedKey)::\(criterionID)"
    }

    func feedbackKey(routineID: String, judge: String) -> String {
        "\(currentDataScopeKey)::\(routineID)::\(judge.normalizedKey)"
    }

    func penaltyKey(routineID: String, judge: String) -> String {
        "\(currentDataScopeKey)::\(routineID)::\(judge.normalizedKey)"
    }

    func score(for routine: Routine, judge: String, criterion: Criterion) -> Double {
        scores[scoreKey(routineID: routine.id, judge: judge, criterionID: criterion.id)]
            ?? scores[legacyScoreKey(routineID: routine.id, judge: judge, criterionID: criterion.id)]
            ?? 0
    }

    func feedbackBody(for routine: Routine, judge: String) -> String {
        feedback[feedbackKey(routineID: routine.id, judge: judge)]
            ?? feedback[legacyFeedbackKey(routineID: routine.id, judge: judge)]
            ?? ""
    }

    func penalty(for routine: Routine, judge: String) -> Double {
        penalties[penaltyKey(routineID: routine.id, judge: judge)]
            ?? penalties[legacyPenaltyKey(routineID: routine.id, judge: judge)]
            ?? 0
    }

    func setScore(_ value: Double, routine: Routine, judge: String, criterion: Criterion) {
        let clamped = min(max(value, 0), criterion.maxScore)
        let key = scoreKey(routineID: routine.id, judge: judge, criterionID: criterion.id)
        scores[key] = clamped
        markScorePending(key)
        persistScores()
    }

    func submitScores(_ values: [(criterion: Criterion, value: Double)], routine: Routine, judge: String, penalty: Double? = nil) {
        var changedKeys: [String] = []
        for item in values {
            let clamped = min(max(item.value, 0), item.criterion.maxScore)
            let key = scoreKey(routineID: routine.id, judge: judge, criterionID: item.criterion.id)
            scores[key] = clamped
            changedKeys.append(key)
        }
        markScoresPending(changedKeys)
        persistScores()
        if let penalty {
            setPenalty(penalty, routine: routine, judge: judge)
        }
    }

    func setFeedback(_ value: String, routine: Routine, judge: String) {
        let key = feedbackKey(routineID: routine.id, judge: judge)
        feedback[key] = value
        markFeedbackPending(key)
        persistFeedback()
    }

    func setPenalty(_ value: Double, routine: Routine, judge: String) {
        let clamped = min(max(value, -100), 0)
        let key = penaltyKey(routineID: routine.id, judge: judge)
        penalties[key] = clamped
        markPenaltyPending(key)
        persistPenalties()
    }

    func isFavorite(_ routine: Routine, category: FavoriteCategory, judge: String? = nil) -> Bool {
        favoriteSelections[favoriteKey(category: category, judge: judge ?? scoringJudge)] == routine.id
    }

    func hasFavorite(_ routine: Routine, judge: String? = nil) -> Bool {
        FavoriteCategory.allCases.contains { isFavorite(routine, category: $0, judge: judge) }
    }

    func toggleFavorite(_ category: FavoriteCategory, routine: Routine, judge: String? = nil) {
        let key = favoriteKey(category: category, judge: judge ?? scoringJudge)
        if favoriteSelections[key] == routine.id {
            favoriteSelections.removeValue(forKey: key)
        } else {
            favoriteSelections[key] = routine.id
        }
        markFavoritePending(key)
        persistFavoriteSelections()
    }

    func startRemoteSyncIfAvailable() async {
        guard !didStartRemote else {
            LoadDiagnostics.log("startRemoteSyncIfAvailable skipped because it already started")
            return
        }
        didStartRemote = true
        LoadDiagnostics.log("startRemoteSyncIfAvailable started")
        await refreshEvents()
    }

    func refreshEvents() async {
        let start = LoadDiagnostics.start()
        guard let remoteRepository else {
            syncStatus = .localOnly
            syncMessage = "Configura SUPABASE_URL y SUPABASE_PUBLISHABLE_KEY para usar online."
            LoadDiagnostics.log("refreshEvents skipped: Supabase not configured")
            return
        }
        syncStatus = .connecting
        syncMessage = "Buscando eventos en Supabase..."
        LoadDiagnostics.log("refreshEvents started selectedEventID=\(selectedEventID ?? "nil")")
        do {
            let events = try await remoteRepository.fetchEvents()
            availableEvents = events
            LoadDiagnostics.log("refreshEvents received events=\(events.count) elapsed=\(LoadDiagnostics.elapsed(since: start))")
            guard let event = events.first(where: { $0.id == selectedEventID })
                ?? events.first(where: \.isActive)
                ?? events.first
            else {
                syncStatus = .offline("No hay eventos en Supabase.")
                syncMessage = "No hay eventos cargados en Supabase."
                LoadDiagnostics.log("refreshEvents finished without events elapsed=\(LoadDiagnostics.elapsed(since: start))")
                return
            }
            LoadDiagnostics.log("refreshEvents selecting event id=\(event.id) name=\"\(event.name)\" active=\(event.isActive)")
            await selectEvent(event)
            LoadDiagnostics.log("refreshEvents finished elapsed=\(LoadDiagnostics.elapsed(since: start))")
        } catch {
            syncStatus = pendingSyncCount > 0 ? .pending : .offline(error.localizedDescription)
            syncMessage = error.localizedDescription
            LoadDiagnostics.log("refreshEvents failed elapsed=\(LoadDiagnostics.elapsed(since: start)) error=\(error.localizedDescription)")
        }
    }

    func selectEvent(_ event: EventSummary) async {
        let start = LoadDiagnostics.start()
        guard let remoteRepository else { return }
        syncStatus = .connecting
        syncMessage = "Cargando \(event.name) desde Supabase..."
        LoadDiagnostics.log("selectEvent started id=\(event.id) name=\"\(event.name)\"")
        do {
            let bundle = try await remoteRepository.fetchEventBundle(eventID: event.id)
            LoadDiagnostics.log("selectEvent fetched bundle id=\(event.id) elapsed=\(LoadDiagnostics.elapsed(since: start))")
            selectedEventID = bundle.event.id
            UserDefaults.standard.set(bundle.event.id, forKey: selectedEventKey)
            let applyStart = LoadDiagnostics.start()
            applyRemoteBundle(bundle)
            LoadDiagnostics.log("selectEvent applied bundle elapsed=\(LoadDiagnostics.elapsed(since: applyStart)) total=\(LoadDiagnostics.elapsed(since: start))")
            let syncStart = LoadDiagnostics.start()
            await syncPending()
            LoadDiagnostics.log("selectEvent syncPending finished elapsed=\(LoadDiagnostics.elapsed(since: syncStart)) total=\(LoadDiagnostics.elapsed(since: start))")
        } catch {
            syncStatus = pendingSyncCount > 0 ? .pending : .offline(error.localizedDescription)
            syncMessage = error.localizedDescription
            LoadDiagnostics.log("selectEvent failed id=\(event.id) elapsed=\(LoadDiagnostics.elapsed(since: start)) error=\(error.localizedDescription)")
        }
    }

    func refreshCurrentEvent() async throws {
        let start = LoadDiagnostics.start()
        guard let remoteRepository else {
            syncStatus = .localOnly
            syncMessage = DataRefreshError.missingRemoteConfiguration.localizedDescription
            LoadDiagnostics.log("refreshCurrentEvent skipped: Supabase not configured")
            throw DataRefreshError.missingRemoteConfiguration
        }

        syncStatus = .connecting
        syncMessage = "Actualizando datos del programa..."
        LoadDiagnostics.log("refreshCurrentEvent started selectedEventID=\(selectedEventID ?? "nil")")

        do {
            let eventID: String
            if let selectedEventID {
                eventID = selectedEventID
            } else {
                let events = try await remoteRepository.fetchEvents()
                availableEvents = events
                guard let event = events.first(where: \.isActive) ?? events.first else {
                    LoadDiagnostics.log("refreshCurrentEvent failed without events elapsed=\(LoadDiagnostics.elapsed(since: start))")
                    throw DataRefreshError.noEvents
                }
                eventID = event.id
            }

            let bundle = try await remoteRepository.fetchEventBundle(eventID: eventID)
            LoadDiagnostics.log("refreshCurrentEvent fetched bundle id=\(eventID) elapsed=\(LoadDiagnostics.elapsed(since: start))")
            selectedEventID = bundle.event.id
            UserDefaults.standard.set(bundle.event.id, forKey: selectedEventKey)
            let applyStart = LoadDiagnostics.start()
            applyRemoteBundle(bundle)
            LoadDiagnostics.log("refreshCurrentEvent applied bundle elapsed=\(LoadDiagnostics.elapsed(since: applyStart)) total=\(LoadDiagnostics.elapsed(since: start))")
            let syncStart = LoadDiagnostics.start()
            await syncPending()
            LoadDiagnostics.log("refreshCurrentEvent syncPending finished elapsed=\(LoadDiagnostics.elapsed(since: syncStart)) total=\(LoadDiagnostics.elapsed(since: start))")
            syncStatus = pendingSyncCount > 0 ? .pending : .online
            syncMessage = pendingSyncCount > 0 ? "\(pendingSyncCount) cambios pendientes." : "\(bundle.event.name) actualizado."
        } catch {
            syncStatus = pendingSyncCount > 0 ? .pending : .offline(error.localizedDescription)
            syncMessage = error.localizedDescription
            LoadDiagnostics.log("refreshCurrentEvent failed elapsed=\(LoadDiagnostics.elapsed(since: start)) error=\(error.localizedDescription)")
            throw error
        }
    }

    func deleteEvent(_ event: EventSummary) async throws {
        guard let remoteRepository else {
            throw EventDeletionError.missingRemoteConfiguration
        }
        guard isAdmin else {
            throw EventDeletionError.notAllowed
        }

        syncStatus = .syncing
        syncMessage = "Borrando \(event.name)..."
        _ = try await remoteRepository.archiveEvent(eventID: event.id)

        let events = try await remoteRepository.fetchEvents()
        availableEvents = events
        if selectedEventID == event.id {
            selectedEventID = nil
            UserDefaults.standard.removeObject(forKey: selectedEventKey)

            if let nextEvent = events.first(where: \.isActive) ?? events.first {
                await selectEvent(nextEvent)
            } else {
                syncStatus = .offline("No hay eventos en Supabase.")
                syncMessage = "\(event.name) borrado. No hay programas cargados."
            }
        } else {
            syncStatus = .online
            syncMessage = "\(event.name) borrado."
        }
    }

    func deleteRoutine(_ routine: Routine, importSecret: String) async throws {
        guard let remoteRepository else {
            throw RoutineDeletionError.missingRemoteConfiguration
        }
        guard isAdmin else {
            throw RoutineDeletionError.notAllowed
        }
        guard let eventID = selectedEventID else {
            throw RoutineDeletionError.missingSelectedEvent
        }
        let cleanImportSecret = importSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanImportSecret.isEmpty else {
            throw RoutineDeletionError.missingImportSecret
        }

        let label = "#\(routine.id) \(routine.name)"
        syncStatus = .syncing
        syncMessage = "Borrando \(label)..."
        _ = try await remoteRepository.deleteRoutine(
            eventID: eventID,
            routineID: routine.id,
            importSecret: cleanImportSecret
        )

        purgeLocalState(forRoutineID: routine.id)
        let bundle = try await remoteRepository.fetchEventBundle(eventID: eventID)
        applyRemoteBundle(bundle)
        await syncPending()
        syncStatus = pendingSyncCount > 0 ? .pending : .online
        syncMessage = "\(label) borrada."
    }

    func updateRoutineLevel(_ routine: Routine, level rawLevel: String) async throws {
        guard let remoteRepository else {
            throw RoutineUpdateError.missingRemoteConfiguration
        }
        guard isAdmin else {
            throw RoutineUpdateError.notAllowed
        }
        guard let eventID = selectedEventID else {
            throw RoutineUpdateError.missingSelectedEvent
        }

        let level = rawLevel.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = "#\(routine.id) \(routine.name)"
        syncStatus = .syncing
        syncMessage = "Actualizando nivel de \(label)..."
        _ = try await remoteRepository.updateRoutineLevel(
            eventID: eventID,
            routineID: routine.id,
            level: level
        )

        let bundle = try await remoteRepository.fetchEventBundle(eventID: eventID)
        applyRemoteBundle(bundle)
        await syncPending()
        syncStatus = pendingSyncCount > 0 ? .pending : .online
        syncMessage = "\(label) actualizado."
    }

    func syncPending() async {
        let start = LoadDiagnostics.start()
        guard let remoteRepository, let eventID = selectedEventID else {
            syncStatus = remoteRepository == nil ? .localOnly : .pending
            LoadDiagnostics.log("syncPending skipped remoteConfigured=\(remoteRepository != nil) eventID=\(selectedEventID ?? "nil")")
            return
        }
        guard pendingSyncCount > 0 else {
            syncStatus = .online
            syncMessage = "Datos sincronizados."
            LoadDiagnostics.log("syncPending skipped no pending changes elapsed=\(LoadDiagnostics.elapsed(since: start))")
            return
        }

        syncStatus = .syncing
        LoadDiagnostics.log("syncPending started eventID=\(eventID) pendingScores=\(pendingScoreKeys.count) pendingFeedback=\(pendingFeedbackKeys.count) pendingPenalties=\(pendingPenaltyKeys.count) pendingFavorites=\(pendingFavoriteKeys.count)")
        do {
            let scoreUploads = pendingScoreKeys.compactMap { key -> (key: String, row: ScoreUpsertRow)? in
                guard
                    let parsed = parseScoreKey(key),
                    let value = scores[key],
                    keyEventMatchesCurrentSelection(parsed.eventID, selectedEventID: eventID),
                    let judgeName = judgeName(forNormalizedKey: parsed.judgeKey)
                else {
                    return nil
                }
                return (key, ScoreUpsertRow(
                    eventID: eventID,
                    routineID: parsed.routineID,
                    judgeID: judgeName.stableRemoteID,
                    criterionID: parsed.criterionID,
                    value: value,
                    deviceID: deviceID
                ))
            }
            let scoreRows = scoreUploads.map { $0.row }
            if !scoreRows.isEmpty {
                let uploadStart = LoadDiagnostics.start()
                try await remoteRepository.upsertScores(scoreRows)
                pendingScoreKeys.subtract(scoreUploads.map { $0.key })
                persistPendingScoreKeys()
                persistScores()
                LoadDiagnostics.log("syncPending uploaded scores=\(scoreRows.count) elapsed=\(LoadDiagnostics.elapsed(since: uploadStart))")
            }

            let feedbackUploads = pendingFeedbackKeys.compactMap { key -> (key: String, row: FeedbackUpsertRow)? in
                guard
                    let parsed = parseFeedbackKey(key),
                    keyEventMatchesCurrentSelection(parsed.eventID, selectedEventID: eventID),
                    let judgeName = judgeName(forNormalizedKey: parsed.judgeKey)
                else {
                    return nil
                }
                return (key, FeedbackUpsertRow(
                    eventID: eventID,
                    routineID: parsed.routineID,
                    judgeID: judgeName.stableRemoteID,
                    body: feedback[key] ?? "",
                    deviceID: deviceID
                ))
            }
            let feedbackRows = feedbackUploads.map { $0.row }
            if !feedbackRows.isEmpty {
                let uploadStart = LoadDiagnostics.start()
                try await remoteRepository.upsertFeedback(feedbackRows)
                pendingFeedbackKeys.subtract(feedbackUploads.map { $0.key })
                persistPendingFeedbackKeys()
                persistFeedback()
                LoadDiagnostics.log("syncPending uploaded feedback=\(feedbackRows.count) elapsed=\(LoadDiagnostics.elapsed(since: uploadStart))")
            }

            let penaltyUploads = pendingPenaltyKeys.compactMap { key -> (key: String, row: PenaltyUpsertRow)? in
                guard
                    let parsed = parsePenaltyKey(key),
                    keyEventMatchesCurrentSelection(parsed.eventID, selectedEventID: eventID),
                    let judgeName = judgeName(forNormalizedKey: parsed.judgeKey)
                else {
                    return nil
                }
                return (key, PenaltyUpsertRow(
                    eventID: eventID,
                    blockID: blockID(forRoutineID: parsed.routineID),
                    routineID: parsed.routineID,
                    judgeID: judgeName.stableRemoteID,
                    value: penalties[key] ?? 0,
                    deviceID: deviceID
                ))
            }
            let penaltyRows = penaltyUploads.map { $0.row }
            if !penaltyRows.isEmpty {
                let uploadStart = LoadDiagnostics.start()
                try await remoteRepository.upsertPenalties(penaltyRows)
                pendingPenaltyKeys.subtract(penaltyUploads.map { $0.key })
                persistPendingPenaltyKeys()
                persistPenalties()
                LoadDiagnostics.log("syncPending uploaded penalties=\(penaltyRows.count) elapsed=\(LoadDiagnostics.elapsed(since: uploadStart))")
            }

            let favoriteKeys = pendingFavoriteKeys
            let favoriteUpsertRows = favoriteKeys.compactMap { key -> FavoriteUpsertRow? in
                guard
                    let parsed = parseFavoriteKey(key),
                    let routineID = favoriteSelections[key],
                    let judgeName = judgeName(forNormalizedKey: parsed.judgeKey)
                else {
                    return nil
                }
                return FavoriteUpsertRow(
                    eventID: eventID,
                    blockID: parsed.blockID,
                    routineID: routineID,
                    judgeID: judgeName.stableRemoteID,
                    category: parsed.category.rawValue,
                    deviceID: deviceID
                )
            }
            let favoriteDeleteRows = favoriteKeys.compactMap { key -> FavoriteDeleteRow? in
                guard
                    favoriteSelections[key] == nil,
                    let parsed = parseFavoriteKey(key),
                    let judgeName = judgeName(forNormalizedKey: parsed.judgeKey)
                else {
                    return nil
                }
                return FavoriteDeleteRow(
                    eventID: eventID,
                    blockID: parsed.blockID,
                    judgeID: judgeName.stableRemoteID,
                    category: parsed.category.rawValue
                )
            }
            if !favoriteUpsertRows.isEmpty {
                let uploadStart = LoadDiagnostics.start()
                try await remoteRepository.upsertFavorites(favoriteUpsertRows)
                LoadDiagnostics.log("syncPending uploaded favorites=\(favoriteUpsertRows.count) elapsed=\(LoadDiagnostics.elapsed(since: uploadStart))")
            }
            if !favoriteDeleteRows.isEmpty {
                let uploadStart = LoadDiagnostics.start()
                try await remoteRepository.deleteFavorites(favoriteDeleteRows)
                LoadDiagnostics.log("syncPending deleted favorites=\(favoriteDeleteRows.count) elapsed=\(LoadDiagnostics.elapsed(since: uploadStart))")
            }
            if !favoriteKeys.isEmpty {
                pendingFavoriteKeys.subtract(favoriteKeys)
                persistPendingFavoriteKeys()
                persistFavoriteSelections()
            }

            syncStatus = pendingSyncCount > 0 ? .pending : .online
            syncMessage = pendingSyncCount > 0 ? "\(pendingSyncCount) cambios pendientes." : "Datos sincronizados."
            LoadDiagnostics.log("syncPending finished pending=\(pendingSyncCount) elapsed=\(LoadDiagnostics.elapsed(since: start))")
        } catch {
            syncStatus = .pending
            syncMessage = error.localizedDescription
            LoadDiagnostics.log("syncPending failed elapsed=\(LoadDiagnostics.elapsed(since: start)) error=\(error.localizedDescription)")
        }
    }

    func result(for routine: Routine) -> RoutineResult {
        let template = template(for: routine)
        let summaries = appData.judges.map { judge in
            let subtotal = template.criteria.reduce(0) { sum, criterion in
                sum + score(for: routine, judge: judge, criterion: criterion)
            }
            let penaltyValue = penalty(for: routine, judge: judge)
            let finalTotal = subtotal > 0 ? max(0, subtotal + penaltyValue) : 0
            return (judge: judge, subtotal: subtotal, penalty: penaltyValue, total: finalTotal)
        }
        let judgeTotals = summaries.map { (judge: $0.judge, total: $0.total) }
        let judgePenalties = summaries.map { (judge: $0.judge, value: $0.penalty) }
        let submitted = summaries.filter { $0.subtotal > 0 }
        let average = submitted.isEmpty ? 0 : submitted.reduce(0) { $0 + $1.total } / Double(submitted.count)
        let aggregatePenalty = submitted.reduce(0) { $0 + $1.penalty }
        return RoutineResult(
            routine: routine,
            judgeTotals: judgeTotals,
            judgePenalties: judgePenalties,
            total: average,
            penalty: aggregatePenalty,
            maxScore: template.maxScore
        )
    }

    func routines(in block: DanceBlock) -> [Routine] {
        let blockRoutineIDs = Set(block.routines.map(\.id))
        return routines
            .filter { routine in
                blockRoutineIDs.contains(routine.id)
                    || routine.blockID == block.id
                    || routine.block == block.name
            }
            .sorted(by: routineOrder)
    }

    func results(in block: DanceBlock) -> [RoutineResult] {
        routines(in: block).map(result)
    }

    var rankings: [RoutineResult] {
        visibleRoutines
            .map(result)
            .sorted {
                if $0.total == $1.total {
                    return (Int($0.routine.id) ?? 0) < (Int($1.routine.id) ?? 0)
                }
                return $0.total > $1.total
            }
    }

    func exportPDF(results exportResults: [RoutineResult]? = nil, title: String = "Calificaciones y dictamen final") {
        let exportJudges = editableJudges.isEmpty ? judges : editableJudges
        let sourceName = selectedBlock?.name ?? appData.sourceName
        lastPDFURL = PDFExporter.export(
            results: exportResults ?? rankings,
            judges: exportJudges,
            sourceName: sourceName,
            title: title,
            templateForRoutine: { [weak self] routine in
                self?.template(for: routine) ?? JudgingTemplate(genre: "General", title: "Hoja de jueceo", maxScore: 0, criteria: [])
            },
            scoreForCriterion: { [weak self] routine, judge, criterion in
                self?.score(for: routine, judge: judge, criterion: criterion) ?? 0
            },
            penaltyForRoutine: { [weak self] routine, judge in
                self?.penalty(for: routine, judge: judge) ?? 0
            }
        )
    }

    func exportDictamenPDF(results exportResults: [RoutineResult]? = nil, title: String = "Dictamen final") {
        let sourceName = selectedBlock?.name ?? appData.sourceName
        lastPDFURL = PDFExporter.exportDictamen(
            results: exportResults ?? rankings,
            sourceName: sourceName,
            title: title
        )
    }

    func driveFolderExists(named folderName: String) async throws -> Bool {
        let drive = try GoogleDriveService.configured()
        let rootFolderName = driveSafeName(folderName, fallback: drive.rootFolderName)
        return try await drive.folderExists(folderPath: [rootFolderName])
    }

    func exportSelectedBlockToDrive(rootFolderName customRootFolderName: String? = nil) async {
        guard let block = selectedBlock else {
            driveExportStatus = .failed("No hay bloque seleccionado.")
            driveExportMessage = "No hay bloque seleccionado."
            return
        }

        let exportJudges = editableJudges
        guard !exportJudges.isEmpty else {
            driveExportStatus = .failed("No hay jueces para exportar.")
            driveExportMessage = "No hay jueces para exportar."
            return
        }

        driveExportStatus = .exporting
        driveExportMessage = "Preparando PDFs de \(block.name)..."
        lastDriveExportSummary = nil

        do {
            let drive = try GoogleDriveService.configured()
            let rootFolderName = driveSafeName(customRootFolderName ?? drive.rootFolderName, fallback: drive.rootFolderName)
            let blockRoutines = routines(in: block)
            let blockFolderName = driveSafeName(block.name, fallback: "Bloque")
            var uploadedFiles: [GoogleDriveUploadedFile] = []
            var skippedEmptySheets = 0

            for academy in uniqueAcademies(in: blockRoutines) {
                let academyRoutines = blockRoutines.filter {
                    driveAcademyName(for: $0).normalizedKey == academy.normalizedKey
                }
                let academyFolderName = driveSafeName(academy, fallback: "Academia")
                for routine in academyRoutines {
                    let routineFolderName = driveSafeName("#\(routine.id) \(routine.name)", fallback: "Coreografía \(routine.id)")
                    for judge in exportJudges {
                        guard hasRecordedScores(for: routine, judge: judge) else {
                            skippedEmptySheets += 1
                            continue
                        }

                        let fileName = "\(routineFolderName) - \(driveSafeName(judge, fallback: "Juez")).pdf"
                        guard let pdfURL = exportJudgingSheetPDF(
                            routine: routine,
                            judge: judge,
                            blockName: block.name,
                            fileName: fileName,
                            rootFolderName: rootFolderName
                        ) else {
                            throw DriveExportError.pdfGenerationFailed
                        }

                        driveExportMessage = "Subiendo \(routineFolderName) - \(judge)..."
                        let uploaded = try await drive.uploadPDF(
                            fileURL: pdfURL,
                            fileName: fileName,
                            folderPath: [rootFolderName, blockFolderName, academyFolderName, routineFolderName]
                        )
                        uploadedFiles.append(uploaded)
                    }
                }
            }

            lastDriveExportSummary = GoogleDriveExportSummary(
                rootFolderName: rootFolderName,
                uploadedFiles: uploadedFiles
            )
            driveExportStatus = .completed(uploadedFiles.count)
            if uploadedFiles.isEmpty {
                driveExportMessage = "No había hojas calificadas para exportar. \(skippedEmptySheets) hojas vacías omitidas."
            } else if skippedEmptySheets > 0 {
                driveExportMessage = "\(uploadedFiles.count) PDFs exportados a \(rootFolderName). \(skippedEmptySheets) hojas vacías omitidas."
            } else {
                driveExportMessage = "\(uploadedFiles.count) PDFs exportados a \(rootFolderName)."
            }
        } catch {
            driveExportStatus = .failed(error.localizedDescription)
            driveExportMessage = error.localizedDescription
        }
    }

    func exportRoutineToDrive(routine: Routine, judge: String) async {
        guard isAdmin else {
            driveExportStatus = .failed("Solo un admin puede exportar esta coreografía.")
            driveExportMessage = "Solo un admin puede exportar esta coreografía."
            return
        }

        guard appData.judges.contains(judge), role(for: judge) == .judge else {
            driveExportStatus = .failed("Elegí un juez para exportar esta coreografía.")
            driveExportMessage = "Elegí un juez para exportar esta coreografía."
            return
        }

        guard let block = block(containing: routine) else {
            driveExportStatus = .failed(DriveExportError.routineBlockNotFound.localizedDescription)
            driveExportMessage = DriveExportError.routineBlockNotFound.localizedDescription
            return
        }

        guard hasRecordedScores(for: routine, judge: judge) else {
            driveExportStatus = .failed("Esta hoja no tiene notas cargadas.")
            driveExportMessage = "No se exportó porque esta hoja todavía está vacía."
            return
        }

        driveExportStatus = .exporting
        driveExportMessage = "Preparando #\(routine.id) \(routine.name)..."
        lastDriveExportSummary = nil

        do {
            let drive = try GoogleDriveService.configured()
            let blockFolderName = driveSafeName(block.name, fallback: "Bloque")
            let academyFolderName = driveSafeName(driveAcademyName(for: routine), fallback: "Academia")
            let routineFolderName = driveSafeName("#\(routine.id) \(routine.name)", fallback: "Coreografía \(routine.id)")
            let fileName = "\(routineFolderName) - \(driveSafeName(judge, fallback: "Juez")).pdf"

            guard let pdfURL = exportJudgingSheetPDF(
                routine: routine,
                judge: judge,
                blockName: block.name,
                fileName: fileName,
                rootFolderName: drive.rootFolderName
            ) else {
                throw DriveExportError.pdfGenerationFailed
            }

            driveExportMessage = "Sobrescribiendo \(fileName)..."
            let uploaded = try await drive.replaceExistingPDF(
                fileURL: pdfURL,
                fileName: fileName,
                folderPath: [drive.rootFolderName, blockFolderName, academyFolderName, routineFolderName]
            )

            lastDriveExportSummary = GoogleDriveExportSummary(
                rootFolderName: drive.rootFolderName,
                uploadedFiles: [uploaded]
            )
            driveExportStatus = .completed(1)
            driveExportMessage = "\(fileName) actualizado en Drive."
        } catch {
            driveExportStatus = .failed(error.localizedDescription)
            driveExportMessage = error.localizedDescription
        }
    }

    func uploadExcelImport(fileURL: URL, eventName: String, eventSlug: String, importSecret: String) async throws -> ExcelImportSummary {
        guard let remoteRepository else {
            throw ExcelImportError.missingRemoteConfiguration
        }
        guard isAdmin else {
            throw ExcelImportError.notAllowed
        }
        let cleanImportSecret = importSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanImportSecret.isEmpty else {
            throw ExcelImportError.missingImportSecret
        }

        let didStartAccessing = fileURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        guard let data = try? Data(contentsOf: fileURL) else {
            throw ExcelImportError.invalidFile
        }

        let maxMegabytes = 20
        let maxBytes = maxMegabytes * 1024 * 1024
        guard data.count <= maxBytes else {
            throw ExcelImportError.fileTooLarge(maxMegabytes: maxMegabytes)
        }

        let cleanEventName = eventName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSlug = eventSlug.stableRemoteID
        let summary = ExcelImportSummary(
            fileName: fileURL.lastPathComponent,
            eventName: cleanEventName,
            eventSlug: cleanSlug,
            fileSize: data.count,
            eventID: nil,
            routineCount: nil
        )
        let row = ExcelImportUploadRow(
            eventSlug: cleanSlug,
            eventName: cleanEventName,
            filename: summary.fileName,
            fileSize: summary.fileSize,
            payloadBase64: data.base64EncodedString(),
            deviceID: deviceID
        )

        syncStatus = .syncing
        syncMessage = "Importando \(summary.fileName) en Supabase..."
        let response = try await remoteRepository.importExcel(row, importSecret: cleanImportSecret)
        let importedSummary = ExcelImportSummary(
            fileName: summary.fileName,
            eventName: response.eventName,
            eventSlug: response.eventSlug,
            fileSize: summary.fileSize,
            eventID: response.eventID,
            routineCount: response.routines
        )

        let events = try await remoteRepository.fetchEvents()
        availableEvents = events
        if let importedEvent = events.first(where: { $0.id == response.eventID })
            ?? events.first(where: { $0.slug == response.eventSlug }) {
            await selectEvent(importedEvent)
        } else {
            syncStatus = .online
            syncMessage = "Evento importado: \(response.eventName)."
        }
        return importedSummary
    }

    private func applyRemoteBundle(_ bundle: RemoteEventBundle) {
        let start = LoadDiagnostics.start()
        LoadDiagnostics.log(
            "applyRemoteBundle started event=\"\(bundle.event.name)\" routines=\(bundle.appData.routines.count) blocks=\(bundle.appData.blocks.count) judges=\(bundle.appData.judges.count) incomingScores=\(bundle.scores.count) incomingFeedback=\(bundle.feedback.count) incomingPenalties=\(bundle.penalties.count) incomingFavorites=\(bundle.favorites.count) localScores=\(scores.count) localFeedback=\(feedback.count) localPenalties=\(penalties.count) pending=\(pendingSyncCount)"
        )
        let metadataStart = LoadDiagnostics.start()
        appData = bundle.appData
        if let selectedBlockID,
           !appData.blocks.contains(where: { $0.id == selectedBlockID || $0.name == selectedBlockID }) {
            self.selectedBlockID = nil
            UserDefaults.standard.removeObject(forKey: selectedBlockKey)
        }
        if selectedBlockID == nil, let defaultBlock = appData.blocks.first(where: { $0.isActive == true }) ?? appData.blocks.first {
            selectedBlockID = defaultBlock.id
            UserDefaults.standard.set(defaultBlock.id, forKey: selectedBlockKey)
        }
        if !visibleRoutines.contains(where: { $0.id == selectedRoutineID }) {
            selectedRoutineID = visibleRoutines.first?.id ?? appData.routines.first?.id ?? ""
        }
        if !appData.judges.contains(selectedJudge) {
            selectedJudge = appData.judges.first ?? "JUEZ"
        }
        if let adminScoringJudge, !appData.judges.contains(adminScoringJudge) || role(for: adminScoringJudge) != .judge {
            self.adminScoringJudge = nil
        }
        if !isAdmin, selectedBlockID == nil, let activeBlock = appData.blocks.first(where: { $0.isActive == true }) {
            selectBlock(activeBlock)
        }
        LoadDiagnostics.log("applyRemoteBundle metadata/selection elapsed=\(LoadDiagnostics.elapsed(since: metadataStart)) selectedBlockID=\(selectedBlockID ?? "nil") selectedRoutineID=\(selectedRoutineID) selectedJudge=\(selectedJudge)")

        let judgeNamesByID = Dictionary(uniqueKeysWithValues: appData.judges.map { ($0.stableRemoteID, $0) })
        let cleanupStart = LoadDiagnostics.start()
        removeSyncedCacheForCurrentEvent()
        LoadDiagnostics.log("applyRemoteBundle cache cleanup elapsed=\(LoadDiagnostics.elapsed(since: cleanupStart)) localScores=\(scores.count) localFeedback=\(feedback.count) localPenalties=\(penalties.count)")

        let scoreStart = LoadDiagnostics.start()
        var updatedScores = scores
        var appliedScores = 0
        var skippedPendingScores = 0
        var skippedUnknownScoreJudges = 0
        for remoteScore in bundle.scores {
            guard let judge = judgeNamesByID[remoteScore.judgeID] else {
                skippedUnknownScoreJudges += 1
                continue
            }
            let key = scoreKey(routineID: remoteScore.routineID, judge: judge, criterionID: remoteScore.criterionID)
            if !pendingScoreKeys.contains(key) {
                updatedScores[key] = remoteScore.value
                appliedScores += 1
            } else {
                skippedPendingScores += 1
            }
        }
        scores = updatedScores
        LoadDiagnostics.log("applyRemoteBundle scores applied=\(appliedScores) skippedPending=\(skippedPendingScores) skippedUnknownJudge=\(skippedUnknownScoreJudges) totalLocal=\(scores.count) elapsed=\(LoadDiagnostics.elapsed(since: scoreStart))")

        let feedbackStart = LoadDiagnostics.start()
        var updatedFeedback = feedback
        var appliedFeedback = 0
        var skippedPendingFeedback = 0
        var skippedUnknownFeedbackJudges = 0
        for remoteFeedback in bundle.feedback {
            guard let judge = judgeNamesByID[remoteFeedback.judgeID] else {
                skippedUnknownFeedbackJudges += 1
                continue
            }
            let key = feedbackKey(routineID: remoteFeedback.routineID, judge: judge)
            if !pendingFeedbackKeys.contains(key) {
                updatedFeedback[key] = remoteFeedback.body
                appliedFeedback += 1
            } else {
                skippedPendingFeedback += 1
            }
        }
        feedback = updatedFeedback
        LoadDiagnostics.log("applyRemoteBundle feedback applied=\(appliedFeedback) skippedPending=\(skippedPendingFeedback) skippedUnknownJudge=\(skippedUnknownFeedbackJudges) totalLocal=\(feedback.count) elapsed=\(LoadDiagnostics.elapsed(since: feedbackStart))")

        let penaltyStart = LoadDiagnostics.start()
        var updatedPenalties = penalties
        var appliedPenalties = 0
        var skippedPendingPenalties = 0
        var skippedUnknownPenaltyJudges = 0
        for remotePenalty in bundle.penalties {
            guard let judge = judgeNamesByID[remotePenalty.judgeID] else {
                skippedUnknownPenaltyJudges += 1
                continue
            }
            let key = penaltyKey(routineID: remotePenalty.routineID, judge: judge)
            if !pendingPenaltyKeys.contains(key) {
                updatedPenalties[key] = min(max(remotePenalty.value, -100), 0)
                appliedPenalties += 1
            } else {
                skippedPendingPenalties += 1
            }
        }
        penalties = updatedPenalties
        LoadDiagnostics.log("applyRemoteBundle penalties applied=\(appliedPenalties) skippedPending=\(skippedPendingPenalties) skippedUnknownJudge=\(skippedUnknownPenaltyJudges) totalLocal=\(penalties.count) elapsed=\(LoadDiagnostics.elapsed(since: penaltyStart))")

        let favoriteStart = LoadDiagnostics.start()
        let eventPrefix = "\(bundle.event.id)::"
        var updatedFavoriteSelections = favoriteSelections
        let staleFavoriteKeys = favoriteSelections.keys.filter { key in
            key.hasPrefix(eventPrefix) && !pendingFavoriteKeys.contains(key)
        }
        for key in staleFavoriteKeys {
            updatedFavoriteSelections.removeValue(forKey: key)
        }
        for remoteFavorite in bundle.favorites {
            guard
                let judge = judgeNamesByID[remoteFavorite.judgeID],
                let category = FavoriteCategory(rawValue: remoteFavorite.category)
            else {
                continue
            }
            let key = favoriteKey(
                eventID: remoteFavorite.eventID,
                blockID: remoteFavorite.blockID,
                category: category,
                judge: judge
            )
            if !pendingFavoriteKeys.contains(key) {
                updatedFavoriteSelections[key] = remoteFavorite.routineID
            }
        }
        favoriteSelections = updatedFavoriteSelections
        LoadDiagnostics.log("applyRemoteBundle favorites staleRemoved=\(staleFavoriteKeys.count) incoming=\(bundle.favorites.count) totalLocal=\(favoriteSelections.count) elapsed=\(LoadDiagnostics.elapsed(since: favoriteStart))")
        syncStatus = pendingSyncCount > 0 ? .pending : .online
        syncMessage = "\(bundle.event.name) cargado."
        LoadDiagnostics.log("applyRemoteBundle finished totalElapsed=\(LoadDiagnostics.elapsed(since: start)) pending=\(pendingSyncCount)")
    }

    private func markScorePending(_ key: String) {
        markScoresPending([key])
    }

    private func markScoresPending(_ keys: [String]) {
        guard remoteRepository != nil, selectedEventID != nil else { return }
        pendingScoreKeys.formUnion(keys)
        persistPendingScoreKeys()
        syncStatus = .pending
        Task { await syncPending() }
    }

    private func markFeedbackPending(_ key: String) {
        guard remoteRepository != nil, selectedEventID != nil else { return }
        pendingFeedbackKeys.insert(key)
        persistPendingFeedbackKeys()
        syncStatus = .pending
        Task { await syncPending() }
    }

    private func markPenaltyPending(_ key: String) {
        guard remoteRepository != nil, selectedEventID != nil else { return }
        pendingPenaltyKeys.insert(key)
        persistPendingPenaltyKeys()
        syncStatus = .pending
        Task { await syncPending() }
    }

    private func markFavoritePending(_ key: String) {
        guard remoteRepository != nil, selectedEventID != nil else { return }
        pendingFavoriteKeys.insert(key)
        persistPendingFavoriteKeys()
        syncStatus = .pending
        Task { await syncPending() }
    }

    private func removeSyncedCacheForCurrentEvent() {
        scores = scores.filter { key, _ in
            guard let parsed = parseScoreKey(key), isCurrentDataScope(parsed.eventID) else { return true }
            return pendingScoreKeys.contains(key)
        }
        feedback = feedback.filter { key, _ in
            guard let parsed = parseFeedbackKey(key), isCurrentDataScope(parsed.eventID) else { return true }
            return pendingFeedbackKeys.contains(key)
        }
        penalties = penalties.filter { key, _ in
            guard let parsed = parsePenaltyKey(key), isCurrentDataScope(parsed.eventID) else { return true }
            return pendingPenaltyKeys.contains(key)
        }
    }

    private func purgeLocalState(forRoutineID routineID: String) {
        appData.routines.removeAll { $0.id == routineID }
        appData.blocks = appData.blocks.map { block in
            DanceBlock(
                blockID: block.blockID,
                name: block.name,
                title: block.title,
                sortOrder: block.sortOrder,
                isActive: block.isActive,
                routines: block.routines.filter { $0.id != routineID }
            )
        }

        if selectedRoutineID == routineID {
            selectedRoutineID = visibleRoutines.first?.id ?? appData.routines.first?.id ?? ""
        }

        scores = scores.filter { entry in
            guard let parsed = parseScoreKey(entry.key) else { return true }
            return !(isCurrentDataScope(parsed.eventID) && parsed.routineID == routineID)
        }
        feedback = feedback.filter { entry in
            guard let parsed = parseFeedbackKey(entry.key) else { return true }
            return !(isCurrentDataScope(parsed.eventID) && parsed.routineID == routineID)
        }
        penalties = penalties.filter { entry in
            guard let parsed = parsePenaltyKey(entry.key) else { return true }
            return !(isCurrentDataScope(parsed.eventID) && parsed.routineID == routineID)
        }

        let removedFavoriteKeys = Set<String>(favoriteSelections.compactMap { entry -> String? in
            guard let parsed = parseFavoriteKey(entry.key), parsed.eventID == currentDataScopeKey, entry.value == routineID else {
                return nil
            }
            return entry.key
        })
        favoriteSelections = favoriteSelections.filter { key, value in
            guard let parsed = parseFavoriteKey(key), parsed.eventID == currentDataScopeKey else { return true }
            return value != routineID
        }

        pendingScoreKeys = Set(pendingScoreKeys.filter { key in
            guard let parsed = parseScoreKey(key) else { return true }
            return !(isCurrentDataScope(parsed.eventID) && parsed.routineID == routineID)
        })
        pendingFeedbackKeys = Set(pendingFeedbackKeys.filter { key in
            guard let parsed = parseFeedbackKey(key) else { return true }
            return !(isCurrentDataScope(parsed.eventID) && parsed.routineID == routineID)
        })
        pendingPenaltyKeys = Set(pendingPenaltyKeys.filter { key in
            guard let parsed = parsePenaltyKey(key) else { return true }
            return !(isCurrentDataScope(parsed.eventID) && parsed.routineID == routineID)
        })
        pendingFavoriteKeys.subtract(removedFavoriteKeys)

        persistPendingScoreKeys()
        persistPendingFeedbackKeys()
        persistPendingPenaltyKeys()
        persistPendingFavoriteKeys()
        persistLocalCaches()
    }

    private func persistScores() {
        Self.saveDictionary(persistedScores, key: scoresKey)
    }

    private func persistFeedback() {
        Self.saveDictionary(persistedFeedback, key: feedbackKey)
    }

    private func persistPenalties() {
        Self.saveDictionary(persistedPenalties, key: penaltiesKey)
    }

    private func persistFavoriteSelections() {
        Self.saveDictionary(persistedFavoriteSelections, key: favoriteSelectionsKey)
    }

    private func persistLocalCaches() {
        persistScores()
        persistFeedback()
        persistPenalties()
        persistFavoriteSelections()
    }

    private var persistedScores: [String: Double] {
        guard remoteRepository != nil else { return scores }
        return scores.filter { pendingScoreKeys.contains($0.key) }
    }

    private var persistedFeedback: [String: String] {
        guard remoteRepository != nil else { return feedback }
        return feedback.filter { pendingFeedbackKeys.contains($0.key) }
    }

    private var persistedPenalties: [String: Double] {
        guard remoteRepository != nil else { return penalties }
        return penalties.filter { pendingPenaltyKeys.contains($0.key) }
    }

    private var persistedFavoriteSelections: [String: String] {
        guard remoteRepository != nil else { return favoriteSelections }
        return favoriteSelections.filter { pendingFavoriteKeys.contains($0.key) }
    }

    private func persistPendingScoreKeys() {
        Self.saveSet(pendingScoreKeys, key: pendingScoreKeysKey)
    }

    private func persistPendingFeedbackKeys() {
        Self.saveSet(pendingFeedbackKeys, key: pendingFeedbackKeysKey)
    }

    private func persistPendingPenaltyKeys() {
        Self.saveSet(pendingPenaltyKeys, key: pendingPenaltyKeysKey)
    }

    private func persistPendingFavoriteKeys() {
        Self.saveSet(pendingFavoriteKeys, key: pendingFavoriteKeysKey)
    }

    private func persistSelectedJudge() {
        UserDefaults.standard.set(selectedJudge, forKey: selectedJudgeKey)
    }

    private var deviceID: String {
        if let existing = UserDefaults.standard.string(forKey: deviceIDKey) {
            return existing
        }
        let created = UUID().uuidString
        UserDefaults.standard.set(created, forKey: deviceIDKey)
        return created
    }

    private var currentDataScopeKey: String {
        selectedEventID ?? appData.sourceName.stableRemoteID
    }

    private func legacyScoreKey(routineID: String, judge: String, criterionID: Int) -> String {
        "\(routineID)::\(judge.normalizedKey)::\(criterionID)"
    }

    private func legacyFeedbackKey(routineID: String, judge: String) -> String {
        "\(routineID)::\(judge.normalizedKey)"
    }

    private func legacyPenaltyKey(routineID: String, judge: String) -> String {
        "\(routineID)::\(judge.normalizedKey)"
    }

    private func parseScoreKey(_ key: String) -> (eventID: String?, routineID: String, judgeKey: String, criterionID: Int)? {
        let parts = key.components(separatedBy: "::")
        if parts.count == 4, let criterionID = Int(parts[3]) {
            return (parts[0], parts[1], parts[2], criterionID)
        }
        if parts.count == 3, let criterionID = Int(parts[2]) {
            return (nil, parts[0], parts[1], criterionID)
        }
        return nil
    }

    private func parseFeedbackKey(_ key: String) -> (eventID: String?, routineID: String, judgeKey: String)? {
        let parts = key.components(separatedBy: "::")
        if parts.count == 3 {
            return (parts[0], parts[1], parts[2])
        }
        if parts.count == 2 {
            return (nil, parts[0], parts[1])
        }
        return nil
    }

    private func parsePenaltyKey(_ key: String) -> (eventID: String?, routineID: String, judgeKey: String)? {
        let parts = key.components(separatedBy: "::")
        if parts.count == 3 {
            return (parts[0], parts[1], parts[2])
        }
        if parts.count == 2 {
            return (nil, parts[0], parts[1])
        }
        return nil
    }

    private func parseFavoriteKey(_ key: String) -> (eventID: String, blockID: String, judgeKey: String, category: FavoriteCategory)? {
        let parts = key.components(separatedBy: "::")
        guard parts.count == 4, let category = FavoriteCategory(rawValue: parts[3]) else { return nil }
        return (parts[0], parts[1], parts[2], category)
    }

    private func judgeName(forNormalizedKey judgeKey: String) -> String? {
        appData.judges.first { $0.normalizedKey == judgeKey || $0.stableRemoteID == judgeKey }
    }

    private func isCurrentDataScope(_ eventID: String?) -> Bool {
        eventID == nil || eventID == currentDataScopeKey
    }

    private func keyEventMatchesCurrentSelection(_ eventID: String?, selectedEventID: String) -> Bool {
        eventID == nil || eventID == selectedEventID
    }

    private func matchesJudgeKey(_ judgeKey: String, judge: String) -> Bool {
        judgeKey == judge
            || judgeKey == judge.normalizedKey
            || judgeKey == judge.stableRemoteID
            || judgeKey.normalizedKey == judge.normalizedKey
            || judgeKey.stableRemoteID == judge.stableRemoteID
    }

    private func favoriteKey(category: FavoriteCategory, judge: String) -> String {
        favoriteKey(eventID: selectedEventID, blockID: selectedBlock?.id, category: category, judge: judge)
    }

    private func favoriteKey(eventID: String?, blockID: String?, category: FavoriteCategory, judge: String) -> String {
        let eventKey = eventID ?? appData.sourceName.stableRemoteID
        let blockKey = blockID ?? "sin-bloque"
        return "\(eventKey)::\(blockKey)::\(judge.normalizedKey)::\(category.rawValue)"
    }

    private func blockName(for blockID: String) -> String {
        blocks.first { $0.id == blockID || $0.name == blockID }?.name ?? blockID
    }

    private func blockSortOrder(named blockName: String) -> Int {
        blocks.first { $0.name == blockName || $0.id == blockName }?.sortOrder ?? Int.max
    }

    private func blockID(forRoutineID routineID: String) -> String {
        guard let routine = routines.first(where: { $0.id == routineID }) else {
            return selectedBlock?.id ?? ""
        }
        return block(containing: routine)?.id ?? routine.blockID ?? routine.block.stableRemoteID
    }

    private func exportJudgingSheetPDF(
        routine: Routine,
        judge: String,
        blockName: String,
        fileName: String,
        rootFolderName: String
    ) -> URL? {
        let template = template(for: routine)
        let feedbackBody = feedbackBody(for: routine, judge: judge)
        return JudgingSheetPDFExporter.export(
            routine: routine,
            judge: judge,
            template: template,
            sourceName: rootFolderName,
            blockName: blockName,
            fileName: fileName,
            feedback: feedbackBody,
            penalty: penalty(for: routine, judge: judge),
            scoreForCriterion: { [weak self] criterion in
                self?.score(for: routine, judge: judge, criterion: criterion) ?? 0
            }
        )
    }

    private func uniqueAcademies(in routines: [Routine]) -> [String] {
        Array(Set(routines.map(driveAcademyName)))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func driveAcademyName(for routine: Routine) -> String {
        let academy = routine.academy.trimmingCharacters(in: .whitespacesAndNewlines)
        return academy.isEmpty ? "Sin academia" : academy
    }

    private func hasRecordedScores(for routine: Routine, judge: String) -> Bool {
        template(for: routine).criteria.contains { criterion in
            score(for: routine, judge: judge, criterion: criterion) > 0
        }
    }

    private func scoreSheetPositions(for results: [RoutineResult], judges: [String]) -> [String: CompetitionPlacement] {
        let grouped = Dictionary(grouping: results) { result in
            [
                result.routine.genre,
                result.routine.division,
                result.routine.level,
                result.routine.category
            ]
            .map(\.normalizedKey)
            .joined(separator: "|")
        }
        var positions: [String: CompetitionPlacement] = [:]

        for items in grouped.values {
            let rankedItems = items
                .map { result in (result: result, total: aggregateScore(for: result, judges: judges)) }
                .filter { $0.total > 0 }
                .sorted { lhs, rhs in
                    if abs(lhs.total - rhs.total) < 0.0001 {
                        return routineOrder(lhs.result.routine, rhs.result.routine)
                    }
                    return lhs.total > rhs.total
                }

            if rankedItems.count == 1, let item = rankedItems.first {
                positions[item.result.routine.id] = CompetitionPlacement.solo(for: item.total)
                continue
            }

            var currentRank = 0
            var previousTotal: Double?
            for (index, item) in rankedItems.enumerated() {
                if previousTotal == nil || abs(item.total - (previousTotal ?? 0)) >= 0.0001 {
                    currentRank = index + 1
                    previousTotal = item.total
                }
                positions[item.result.routine.id] = currentRank <= 3 ? .position(currentRank) : .participation
            }
        }
        return positions
    }

    private func aggregateScore(for result: RoutineResult, judges: [String]) -> Double {
        let totalsByJudge = Dictionary(uniqueKeysWithValues: result.judgeTotals.map { ($0.judge, $0.total) })
        return judges.reduce(0) { sum, judge in
            sum + (totalsByJudge[judge] ?? 0)
        }
    }

    private func routineOrder(_ lhs: Routine, _ rhs: Routine) -> Bool {
        let lhsNumber = Int(lhs.id) ?? Int.max
        let rhsNumber = Int(rhs.id) ?? Int.max
        if lhsNumber == rhsNumber {
            return lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
        }
        return lhsNumber < rhsNumber
    }

    private func driveSafeName(_ name: String, fallback: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = trimmed
            .map { character -> Character in
                let forbidden: Set<Character> = ["/", "\\", ":", "*", "?", "\"", "<", ">", "|"]
                return forbidden.contains(character) ? "-" : character
            }
        let compact = String(cleaned)
            .split(separator: " ")
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return compact.isEmpty ? fallback : compact
    }

    private func block(containing routine: Routine) -> DanceBlock? {
        blocks.first { block in
            block.routines.contains { $0.id == routine.id }
                || routine.blockID == block.id
                || routine.block == block.name
        }
    }

    private func appendOrUpdateJudgeProfile(name: String, role: UserRole) {
        let profile = JudgeProfile(judgeID: name.stableRemoteID, name: name, role: role)
        var profiles = appData.judgeProfiles ?? []
        if let index = profiles.firstIndex(where: { $0.judgeID == profile.judgeID }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        appData.judgeProfiles = profiles
    }

    private func showOperationNotice(kind: OperationNoticeKind, title: String, message: String) {
        operationNoticeTask?.cancel()
        let notice = OperationNotice(kind: kind, title: title, message: message)
        operationNotice = notice
        operationNoticeTask = Task { [weak self, noticeID = notice.id] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            await MainActor.run {
                guard self?.operationNotice?.id == noticeID else { return }
                self?.operationNotice = nil
                self?.operationNoticeTask = nil
            }
        }
    }

    private static func loadBundledData() -> AppData {
        guard let url = Bundle.main.url(forResource: "app_data", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(AppData.self, from: data)
        else {
            return AppData(sourceName: "Sin datos", blocks: [], routines: [], templates: [], judges: ["JUEZ"], judgeProfiles: nil)
        }
        return decoded
    }

    private static func loadDictionary<T: Decodable>(_ key: String) -> [String: T]? {
        let start = LoadDiagnostics.start()
        guard let data = UserDefaults.standard.data(forKey: key) else {
            LoadDiagnostics.log("UserDefaults load key=\(key) missing elapsed=\(LoadDiagnostics.elapsed(since: start))")
            return nil
        }
        do {
            let decoded = try JSONDecoder().decode([String: T].self, from: data)
            LoadDiagnostics.log("UserDefaults load key=\(key) rows=\(decoded.count) bytes=\(data.count) elapsed=\(LoadDiagnostics.elapsed(since: start))")
            return decoded
        } catch {
            LoadDiagnostics.log("UserDefaults load key=\(key) failed bytes=\(data.count) elapsed=\(LoadDiagnostics.elapsed(since: start)) error=\(error.localizedDescription)")
            return nil
        }
    }

    private static func saveDictionary<T: Encodable>(_ dictionary: [String: T], key: String) {
        let start = LoadDiagnostics.start()
        guard !dictionary.isEmpty else {
            UserDefaults.standard.removeObject(forKey: key)
            LoadDiagnostics.log("UserDefaults save key=\(key) removed empty dictionary elapsed=\(LoadDiagnostics.elapsed(since: start))")
            return
        }
        guard let data = try? JSONEncoder().encode(dictionary) else {
            LoadDiagnostics.log("UserDefaults save key=\(key) failed rows=\(dictionary.count) elapsed=\(LoadDiagnostics.elapsed(since: start))")
            return
        }
        UserDefaults.standard.set(data, forKey: key)
        LoadDiagnostics.log("UserDefaults save key=\(key) rows=\(dictionary.count) bytes=\(data.count) elapsed=\(LoadDiagnostics.elapsed(since: start))")
    }

    private static func removeStoredValue(_ key: String) {
        guard UserDefaults.standard.object(forKey: key) != nil else { return }
        UserDefaults.standard.removeObject(forKey: key)
        LoadDiagnostics.log("UserDefaults removed legacy key=\(key)")
    }

    private static func loadSet(_ key: String) -> Set<String> {
        guard let values = UserDefaults.standard.array(forKey: key) as? [String] else { return [] }
        return Set(values)
    }

    private static func saveSet(_ values: Set<String>, key: String) {
        UserDefaults.standard.set(Array(values).sorted(), forKey: key)
    }
}
