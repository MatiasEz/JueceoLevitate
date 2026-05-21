import Foundation
import SwiftUI

private enum DriveExportError: LocalizedError {
    case pdfGenerationFailed

    var errorDescription: String? {
        switch self {
        case .pdfGenerationFailed:
            "No se pudo generar el PDF de calificaciones."
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
    @Published var scores: [String: Double] = [:] {
        didSet { persistScores() }
    }
    @Published var feedback: [String: String] = [:] {
        didSet { persistFeedback() }
    }
    @Published var penalties: [String: Double] = [:] {
        didSet { persistPenalties() }
    }
    @Published var favoriteSelections: [String: String] = [:] {
        didSet { persistFavoriteSelections() }
    }
    @Published var lastPDFURL: URL?
    @Published private(set) var driveExportStatus: DriveExportStatus = .idle
    @Published private(set) var driveExportMessage: String?
    @Published private(set) var lastDriveExportSummary: GoogleDriveExportSummary?

    private let scoresKey = "jueceo.scores.v1"
    private let feedbackKey = "jueceo.feedback.v1"
    private let penaltiesKey = "jueceo.penalties.v1"
    private let favoriteSelectionsKey = "jueceo.favoriteSelections.v1"
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

    init() {
        let data = Self.loadBundledData()
        appData = data
        selectedRoutineID = data.routines.first?.id ?? ""
        let savedJudge = UserDefaults.standard.string(forKey: selectedJudgeKey)
        selectedJudge = savedJudge.flatMap { data.judges.contains($0) ? $0 : nil }
            ?? data.judges.first
            ?? "JUEZ"
        scores = Self.loadDictionary(scoresKey) ?? [:]
        feedback = Self.loadDictionary(feedbackKey) ?? [:]
        penalties = Self.loadDictionary(penaltiesKey) ?? [:]
        favoriteSelections = Self.loadDictionary(favoriteSelectionsKey) ?? [:]
        pendingScoreKeys = Self.loadSet(pendingScoreKeysKey)
        pendingFeedbackKeys = Self.loadSet(pendingFeedbackKeysKey)
        pendingPenaltyKeys = Self.loadSet(pendingPenaltyKeysKey)
        pendingFavoriteKeys = Self.loadSet(pendingFavoriteKeysKey)
        selectedEventID = UserDefaults.standard.string(forKey: selectedEventKey)
        selectedBlockID = UserDefaults.standard.string(forKey: selectedBlockKey)
        if let config = SupabaseConfig.load() {
            remoteRepository = RemoteJudgingRepository(config: config)
            syncStatus = pendingSyncCount > 0 ? .pending : .connecting
        } else {
            remoteRepository = nil
            syncStatus = .localOnly
        }
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
        return visible.isEmpty ? routines : visible
    }
    var hasRemoteConfiguration: Bool { remoteRepository != nil }
    var hasGoogleDriveConfiguration: Bool { GoogleDriveConfig.load() != nil }
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

    func addJudge(_ name: String) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !cleanName.isEmpty, !appData.judges.contains(cleanName) else { return }
        appData.judges.append(cleanName)
        appendOrUpdateJudgeProfile(name: cleanName, role: cleanName.stableRemoteID == "ati" ? .admin : .judge)
        selectJudge(cleanName)
    }

    func canDeleteJudge(_ judge: String) -> Bool {
        appData.judges.contains(judge) && role(for: judge) != .admin
    }

    func deleteJudge(_ judge: String) {
        guard canDeleteJudge(judge) else { return }

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
            return !matchesJudgeKey(parsed.judgeKey, judge: judge)
        }
        feedback = feedback.filter { key, _ in
            guard let parsed = parseFeedbackKey(key) else { return true }
            return !matchesJudgeKey(parsed.judgeKey, judge: judge)
        }
        penalties = penalties.filter { key, _ in
            guard let parsed = parsePenaltyKey(key) else { return true }
            return !matchesJudgeKey(parsed.judgeKey, judge: judge)
        }
        favoriteSelections = favoriteSelections.filter { key, _ in
            guard let parsed = parseFavoriteKey(key) else { return true }
            return !matchesJudgeKey(parsed.judgeKey, judge: judge)
        }

        pendingScoreKeys = pendingScoreKeys.filter { key in
            guard let parsed = parseScoreKey(key) else { return true }
            return !matchesJudgeKey(parsed.judgeKey, judge: judge)
        }
        pendingFeedbackKeys = pendingFeedbackKeys.filter { key in
            guard let parsed = parseFeedbackKey(key) else { return true }
            return !matchesJudgeKey(parsed.judgeKey, judge: judge)
        }
        pendingPenaltyKeys = pendingPenaltyKeys.filter { key in
            guard let parsed = parsePenaltyKey(key) else { return true }
            return !matchesJudgeKey(parsed.judgeKey, judge: judge)
        }
        pendingFavoriteKeys = pendingFavoriteKeys.filter { key in
            guard let parsed = parseFavoriteKey(key) else { return true }
            return !matchesJudgeKey(parsed.judgeKey, judge: judge)
        }
        persistPendingScoreKeys()
        persistPendingFeedbackKeys()
        persistPendingPenaltyKeys()
        persistPendingFavoriteKeys()

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

    func selectBlock(_ block: DanceBlock) {
        selectedBlockID = block.id
        UserDefaults.standard.set(block.id, forKey: selectedBlockKey)
        let nextRoutine = block.routines.first
            ?? routines.first { $0.blockID == block.id || $0.block == block.name }
            ?? routines.first
        selectedRoutineID = nextRoutine?.id ?? ""
    }

    func scoreKey(routineID: String, judge: String, criterionID: Int) -> String {
        "\(routineID)::\(judge.normalizedKey)::\(criterionID)"
    }

    func feedbackKey(routineID: String, judge: String) -> String {
        "\(routineID)::\(judge.normalizedKey)"
    }

    func penaltyKey(routineID: String, judge: String) -> String {
        "\(routineID)::\(judge.normalizedKey)"
    }

    func score(for routine: Routine, judge: String, criterion: Criterion) -> Double {
        scores[scoreKey(routineID: routine.id, judge: judge, criterionID: criterion.id)] ?? 0
    }

    func penalty(for routine: Routine, judge: String) -> Double {
        penalties[penaltyKey(routineID: routine.id, judge: judge)] ?? 0
    }

    func setScore(_ value: Double, routine: Routine, judge: String, criterion: Criterion) {
        let clamped = min(max(value, 0), criterion.maxScore)
        let key = scoreKey(routineID: routine.id, judge: judge, criterionID: criterion.id)
        scores[key] = clamped
        markScorePending(key)
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
        if let penalty {
            setPenalty(penalty, routine: routine, judge: judge)
        }
    }

    func setFeedback(_ value: String, routine: Routine, judge: String) {
        let key = feedbackKey(routineID: routine.id, judge: judge)
        feedback[key] = value
        markFeedbackPending(key)
    }

    func setPenalty(_ value: Double, routine: Routine, judge: String) {
        let clamped = min(max(value, -100), 0)
        let key = penaltyKey(routineID: routine.id, judge: judge)
        penalties[key] = clamped
        markPenaltyPending(key)
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
    }

    func startRemoteSyncIfAvailable() async {
        guard !didStartRemote else { return }
        didStartRemote = true
        await refreshEvents()
    }

    func refreshEvents() async {
        guard let remoteRepository else {
            syncStatus = .localOnly
            syncMessage = "Configura SUPABASE_URL y SUPABASE_PUBLISHABLE_KEY para usar online."
            return
        }
        syncStatus = .connecting
        syncMessage = "Buscando eventos en Supabase..."
        do {
            let events = try await remoteRepository.fetchEvents()
            availableEvents = events
            guard let event = events.first(where: { $0.id == selectedEventID })
                ?? events.first(where: \.isActive)
                ?? events.first
            else {
                syncStatus = .offline("No hay eventos en Supabase.")
                syncMessage = "No hay eventos cargados en Supabase."
                return
            }
            await selectEvent(event)
        } catch {
            syncStatus = pendingSyncCount > 0 ? .pending : .offline(error.localizedDescription)
            syncMessage = error.localizedDescription
        }
    }

    func selectEvent(_ event: EventSummary) async {
        guard let remoteRepository else { return }
        syncStatus = .connecting
        syncMessage = "Cargando \(event.name) desde Supabase..."
        do {
            let bundle = try await remoteRepository.fetchEventBundle(eventID: event.id)
            selectedEventID = bundle.event.id
            UserDefaults.standard.set(bundle.event.id, forKey: selectedEventKey)
            applyRemoteBundle(bundle)
            await syncPending()
        } catch {
            syncStatus = pendingSyncCount > 0 ? .pending : .offline(error.localizedDescription)
            syncMessage = error.localizedDescription
        }
    }

    func syncPending() async {
        guard let remoteRepository, let eventID = selectedEventID else {
            syncStatus = remoteRepository == nil ? .localOnly : .pending
            return
        }
        guard pendingSyncCount > 0 else {
            syncStatus = .online
            syncMessage = "Datos sincronizados."
            return
        }

        syncStatus = .syncing
        do {
            let scoreRows = pendingScoreKeys.compactMap { key -> ScoreUpsertRow? in
                guard
                    let parsed = parseScoreKey(key),
                    let value = scores[key],
                    judgeName(forNormalizedKey: parsed.judgeKey) != nil
                else {
                    return nil
                }
                return ScoreUpsertRow(
                    eventID: eventID,
                    routineID: parsed.routineID,
                    judgeID: parsed.judgeKey.stableRemoteID,
                    criterionID: parsed.criterionID,
                    value: value,
                    deviceID: deviceID
                )
            }
            if !scoreRows.isEmpty {
                try await remoteRepository.upsertScores(scoreRows)
                pendingScoreKeys.subtract(scoreRows.map { scoreKey(routineID: $0.routineID, judge: $0.judgeID, criterionID: $0.criterionID) })
                pendingScoreKeys.removeAll()
                persistPendingScoreKeys()
            }

            let feedbackRows = pendingFeedbackKeys.compactMap { key -> FeedbackUpsertRow? in
                guard
                    let parsed = parseFeedbackKey(key),
                    let judgeName = judgeName(forNormalizedKey: parsed.judgeKey)
                else {
                    return nil
                }
                return FeedbackUpsertRow(
                    eventID: eventID,
                    routineID: parsed.routineID,
                    judgeID: judgeName.stableRemoteID,
                    body: feedback[key] ?? "",
                    deviceID: deviceID
                )
            }
            if !feedbackRows.isEmpty {
                try await remoteRepository.upsertFeedback(feedbackRows)
                pendingFeedbackKeys.removeAll()
                persistPendingFeedbackKeys()
            }

            let penaltyRows = pendingPenaltyKeys.compactMap { key -> PenaltyUpsertRow? in
                guard
                    let parsed = parsePenaltyKey(key),
                    let judgeName = judgeName(forNormalizedKey: parsed.judgeKey)
                else {
                    return nil
                }
                return PenaltyUpsertRow(
                    eventID: eventID,
                    blockID: blockID(forRoutineID: parsed.routineID),
                    routineID: parsed.routineID,
                    judgeID: judgeName.stableRemoteID,
                    value: penalties[key] ?? 0,
                    deviceID: deviceID
                )
            }
            if !penaltyRows.isEmpty {
                try await remoteRepository.upsertPenalties(penaltyRows)
                pendingPenaltyKeys.removeAll()
                persistPendingPenaltyKeys()
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
                try await remoteRepository.upsertFavorites(favoriteUpsertRows)
            }
            if !favoriteDeleteRows.isEmpty {
                try await remoteRepository.deleteFavorites(favoriteDeleteRows)
            }
            if !favoriteKeys.isEmpty {
                pendingFavoriteKeys.subtract(favoriteKeys)
                persistPendingFavoriteKeys()
            }

            syncStatus = pendingSyncCount > 0 ? .pending : .online
            syncMessage = pendingSyncCount > 0 ? "\(pendingSyncCount) cambios pendientes." : "Datos sincronizados."
        } catch {
            syncStatus = .pending
            syncMessage = error.localizedDescription
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

    func exportSelectedBlockToDrive() async {
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
            let blockRoutines = routines(in: block)
            let blockFolderName = driveSafeName(block.name, fallback: "Bloque")
            var uploadedFiles: [GoogleDriveUploadedFile] = []

            for academy in uniqueAcademies(in: blockRoutines) {
                let academyRoutines = blockRoutines.filter {
                    driveAcademyName(for: $0).normalizedKey == academy.normalizedKey
                }
                let academyFolderName = driveSafeName(academy, fallback: "Academia")
                for routine in academyRoutines {
                    let routineFolderName = driveSafeName("#\(routine.id) \(routine.name)", fallback: "Coreografía \(routine.id)")
                    for judge in exportJudges {
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

                        driveExportMessage = "Subiendo \(routineFolderName) - \(judge)..."
                        let uploaded = try await drive.uploadPDF(
                            fileURL: pdfURL,
                            fileName: fileName,
                            folderPath: [drive.rootFolderName, blockFolderName, academyFolderName, routineFolderName]
                        )
                        uploadedFiles.append(uploaded)
                    }
                }
            }

            lastDriveExportSummary = GoogleDriveExportSummary(
                rootFolderName: drive.rootFolderName,
                uploadedFiles: uploadedFiles
            )
            driveExportStatus = .completed(uploadedFiles.count)
            driveExportMessage = "\(uploadedFiles.count) PDFs exportados a \(drive.rootFolderName)."
        } catch {
            driveExportStatus = .failed(error.localizedDescription)
            driveExportMessage = error.localizedDescription
        }
    }

    func uploadExcelImport(fileURL: URL, eventName: String, eventSlug: String) async throws -> ExcelImportSummary {
        guard let remoteRepository else {
            throw ExcelImportError.missingRemoteConfiguration
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
            fileSize: data.count
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
        syncMessage = "Subiendo \(summary.fileName)..."
        try await remoteRepository.uploadExcelImport(row)
        syncStatus = .online
        syncMessage = "Excel subido: \(summary.eventName)."
        return summary
    }

    private func applyRemoteBundle(_ bundle: RemoteEventBundle) {
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

        let judgeNamesByID = Dictionary(uniqueKeysWithValues: appData.judges.map { ($0.stableRemoteID, $0) })
        for remoteScore in bundle.scores {
            guard let judge = judgeNamesByID[remoteScore.judgeID] else { continue }
            let key = scoreKey(routineID: remoteScore.routineID, judge: judge, criterionID: remoteScore.criterionID)
            if !pendingScoreKeys.contains(key) {
                scores[key] = remoteScore.value
            }
        }
        for remoteFeedback in bundle.feedback {
            guard let judge = judgeNamesByID[remoteFeedback.judgeID] else { continue }
            let key = feedbackKey(routineID: remoteFeedback.routineID, judge: judge)
            if !pendingFeedbackKeys.contains(key) {
                feedback[key] = remoteFeedback.body
            }
        }
        for remotePenalty in bundle.penalties {
            guard let judge = judgeNamesByID[remotePenalty.judgeID] else { continue }
            let key = penaltyKey(routineID: remotePenalty.routineID, judge: judge)
            if !pendingPenaltyKeys.contains(key) {
                penalties[key] = min(max(remotePenalty.value, -100), 0)
            }
        }

        let eventPrefix = "\(bundle.event.id)::"
        let staleFavoriteKeys = favoriteSelections.keys.filter { key in
            key.hasPrefix(eventPrefix) && !pendingFavoriteKeys.contains(key)
        }
        for key in staleFavoriteKeys {
            favoriteSelections.removeValue(forKey: key)
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
                favoriteSelections[key] = remoteFavorite.routineID
            }
        }
        syncStatus = pendingSyncCount > 0 ? .pending : .online
        syncMessage = "\(bundle.event.name) cargado."
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

    private func persistScores() {
        Self.saveDictionary(scores, key: scoresKey)
    }

    private func persistFeedback() {
        Self.saveDictionary(feedback, key: feedbackKey)
    }

    private func persistPenalties() {
        Self.saveDictionary(penalties, key: penaltiesKey)
    }

    private func persistFavoriteSelections() {
        Self.saveDictionary(favoriteSelections, key: favoriteSelectionsKey)
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

    private func parseScoreKey(_ key: String) -> (routineID: String, judgeKey: String, criterionID: Int)? {
        let parts = key.components(separatedBy: "::")
        guard parts.count == 3, let criterionID = Int(parts[2]) else { return nil }
        return (parts[0], parts[1], criterionID)
    }

    private func parseFeedbackKey(_ key: String) -> (routineID: String, judgeKey: String)? {
        let parts = key.components(separatedBy: "::")
        guard parts.count == 2 else { return nil }
        return (parts[0], parts[1])
    }

    private func parsePenaltyKey(_ key: String) -> (routineID: String, judgeKey: String)? {
        let parts = key.components(separatedBy: "::")
        guard parts.count == 2 else { return nil }
        return (parts[0], parts[1])
    }

    private func parseFavoriteKey(_ key: String) -> (eventID: String, blockID: String, judgeKey: String, category: FavoriteCategory)? {
        let parts = key.components(separatedBy: "::")
        guard parts.count == 4, let category = FavoriteCategory(rawValue: parts[3]) else { return nil }
        return (parts[0], parts[1], parts[2], category)
    }

    private func judgeName(forNormalizedKey judgeKey: String) -> String? {
        appData.judges.first { $0.normalizedKey == judgeKey || $0.stableRemoteID == judgeKey }
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
        let feedbackBody = feedback[feedbackKey(routineID: routine.id, judge: judge)] ?? ""
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

    private func scoreSheetPositions(for results: [RoutineResult], judges: [String]) -> [String: Int] {
        let grouped = Dictionary(grouping: results) { result in
            [
                result.routine.genre,
                result.routine.division,
                result.routine.category
            ]
            .map(\.normalizedKey)
            .joined(separator: "|")
        }
        var positions: [String: Int] = [:]

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

            var currentRank = 0
            var previousTotal: Double?
            for (index, item) in rankedItems.enumerated() {
                if previousTotal == nil || abs(item.total - (previousTotal ?? 0)) >= 0.0001 {
                    currentRank = index + 1
                    previousTotal = item.total
                }
                positions[item.result.routine.id] = currentRank
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
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode([String: T].self, from: data)
    }

    private static func saveDictionary<T: Encodable>(_ dictionary: [String: T], key: String) {
        guard let data = try? JSONEncoder().encode(dictionary) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private static func loadSet(_ key: String) -> Set<String> {
        guard let values = UserDefaults.standard.array(forKey: key) as? [String] else { return [] }
        return Set(values)
    }

    private static func saveSet(_ values: Set<String>, key: String) {
        UserDefaults.standard.set(Array(values).sorted(), forKey: key)
    }
}
