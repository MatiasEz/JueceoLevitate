import Foundation
import SwiftUI

@MainActor
final class JudgingStore: ObservableObject {
    @Published private(set) var appData: AppData
    @Published private(set) var availableEvents: [EventSummary] = []
    @Published private(set) var selectedEventID: String?
    @Published private(set) var syncStatus: SyncStatus = .localOnly
    @Published private(set) var syncMessage: String?
    @Published var selectedRoutineID: String
    @Published var selectedJudge: String
    @Published var scores: [String: Double] = [:] {
        didSet { persistScores() }
    }
    @Published var feedback: [String: String] = [:] {
        didSet { persistFeedback() }
    }
    @Published var lastPDFURL: URL?

    private let scoresKey = "jueceo.scores.v1"
    private let feedbackKey = "jueceo.feedback.v1"
    private let pendingScoreKeysKey = "jueceo.pendingScoreKeys.v1"
    private let pendingFeedbackKeysKey = "jueceo.pendingFeedbackKeys.v1"
    private let selectedEventKey = "jueceo.selectedEventID.v1"
    private let deviceIDKey = "jueceo.deviceID.v1"
    private var pendingScoreKeys: Set<String> = []
    private var pendingFeedbackKeys: Set<String> = []
    private let remoteRepository: RemoteJudgingRepository?
    private var didStartRemote = false

    init() {
        let data = Self.loadBundledData()
        appData = data
        selectedRoutineID = data.routines.first?.id ?? ""
        selectedJudge = data.judges.first ?? "JUEZ"
        scores = Self.loadDictionary(scoresKey) ?? [:]
        feedback = Self.loadDictionary(feedbackKey) ?? [:]
        pendingScoreKeys = Self.loadSet(pendingScoreKeysKey)
        pendingFeedbackKeys = Self.loadSet(pendingFeedbackKeysKey)
        selectedEventID = UserDefaults.standard.string(forKey: selectedEventKey)
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
    var blocks: [DanceBlock] { appData.blocks }
    var hasRemoteConfiguration: Bool { remoteRepository != nil }
    var pendingSyncCount: Int { pendingScoreKeys.count + pendingFeedbackKeys.count }

    var selectedRoutine: Routine? {
        routines.first { $0.id == selectedRoutineID } ?? routines.first
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
        selectedJudge = cleanName
    }

    func scoreKey(routineID: String, judge: String, criterionID: Int) -> String {
        "\(routineID)::\(judge.normalizedKey)::\(criterionID)"
    }

    func feedbackKey(routineID: String, judge: String) -> String {
        "\(routineID)::\(judge.normalizedKey)"
    }

    func score(for routine: Routine, judge: String, criterion: Criterion) -> Double {
        scores[scoreKey(routineID: routine.id, judge: judge, criterionID: criterion.id)] ?? 0
    }

    func setScore(_ value: Double, routine: Routine, judge: String, criterion: Criterion) {
        let clamped = min(max(value, 0), criterion.maxScore)
        let key = scoreKey(routineID: routine.id, judge: judge, criterionID: criterion.id)
        scores[key] = clamped
        markScorePending(key)
    }

    func submitScores(_ values: [(criterion: Criterion, value: Double)], routine: Routine, judge: String) {
        var changedKeys: [String] = []
        for item in values {
            let clamped = min(max(item.value, 0), item.criterion.maxScore)
            let key = scoreKey(routineID: routine.id, judge: judge, criterionID: item.criterion.id)
            scores[key] = clamped
            changedKeys.append(key)
        }
        markScoresPending(changedKeys)
    }

    func setFeedback(_ value: String, routine: Routine, judge: String) {
        let key = feedbackKey(routineID: routine.id, judge: judge)
        feedback[key] = value
        markFeedbackPending(key)
    }

    func startRemoteSyncIfAvailable() async {
        guard !didStartRemote else { return }
        didStartRemote = true
        await refreshEvents()
    }

    func refreshEvents() async {
        guard let remoteRepository else {
            syncStatus = .localOnly
            syncMessage = "Configura SUPABASE_URL y SUPABASE_ANON_KEY para usar online."
            return
        }
        syncStatus = .connecting
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
        syncMessage = "Cargando \(event.name)..."
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

            syncStatus = pendingSyncCount > 0 ? .pending : .online
            syncMessage = pendingSyncCount > 0 ? "\(pendingSyncCount) cambios pendientes." : "Datos sincronizados."
        } catch {
            syncStatus = .pending
            syncMessage = error.localizedDescription
        }
    }

    func result(for routine: Routine) -> RoutineResult {
        let template = template(for: routine)
        let judgeTotals = appData.judges.map { judge in
            let total = template.criteria.reduce(0) { sum, criterion in
                sum + score(for: routine, judge: judge, criterion: criterion)
            }
            return (judge: judge, total: total)
        }
        let submitted = judgeTotals.filter { $0.total > 0 }
        let average = submitted.isEmpty ? 0 : submitted.reduce(0) { $0 + $1.total } / Double(submitted.count)
        return RoutineResult(routine: routine, judgeTotals: judgeTotals, total: average, maxScore: template.maxScore)
    }

    var rankings: [RoutineResult] {
        routines
            .map(result)
            .sorted {
                if $0.total == $1.total {
                    return (Int($0.routine.id) ?? 0) < (Int($1.routine.id) ?? 0)
                }
                return $0.total > $1.total
            }
    }

    func exportPDF() {
        lastPDFURL = PDFExporter.export(results: rankings, judges: judges, sourceName: appData.sourceName)
    }

    private func applyRemoteBundle(_ bundle: RemoteEventBundle) {
        appData = bundle.appData
        if !appData.routines.contains(where: { $0.id == selectedRoutineID }) {
            selectedRoutineID = appData.routines.first?.id ?? ""
        }
        if !appData.judges.contains(selectedJudge) {
            selectedJudge = appData.judges.first ?? "JUEZ"
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

    private func persistScores() {
        Self.saveDictionary(scores, key: scoresKey)
    }

    private func persistFeedback() {
        Self.saveDictionary(feedback, key: feedbackKey)
    }

    private func persistPendingScoreKeys() {
        Self.saveSet(pendingScoreKeys, key: pendingScoreKeysKey)
    }

    private func persistPendingFeedbackKeys() {
        Self.saveSet(pendingFeedbackKeys, key: pendingFeedbackKeysKey)
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

    private func judgeName(forNormalizedKey judgeKey: String) -> String? {
        appData.judges.first { $0.normalizedKey == judgeKey || $0.stableRemoteID == judgeKey }
    }

    private static func loadBundledData() -> AppData {
        guard let url = Bundle.main.url(forResource: "app_data", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(AppData.self, from: data)
        else {
            return AppData(sourceName: "Sin datos", blocks: [], routines: [], templates: [], judges: ["JUEZ"])
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
