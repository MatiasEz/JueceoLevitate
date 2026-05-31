import Foundation

enum LoadDiagnostics {
    static var isEnabled: Bool {
        #if DEBUG
        true
        #else
        ProcessInfo.processInfo.environment["LEVITATE_LOAD_LOGS"] == "1"
        #endif
    }

    static func start() -> Date {
        Date()
    }

    static func elapsed(since start: Date) -> String {
        String(format: "%.3fs", -start.timeIntervalSinceNow)
    }

    static func log(_ message: String) {
        guard isEnabled else { return }
        print("[LevitateLoad] \(message)")
    }

    static func tableName(from path: String) -> String {
        path.split(separator: "?").first.map(String.init) ?? path
    }
}

struct SupabaseConfig: Sendable {
    let url: URL
    let apiKey: String

    static func load() -> SupabaseConfig? {
        let environment = ProcessInfo.processInfo.environment
        let rawURL = environment["SUPABASE_URL"]
            ?? Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String
        let rawKey = environment["SUPABASE_PUBLISHABLE_KEY"]
            ?? environment["SUPABASE_ANON_KEY"]
            ?? Bundle.main.object(forInfoDictionaryKey: "SUPABASE_PUBLISHABLE_KEY") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String

        guard
            let rawURL,
            let url = URL(string: rawURL.trimmingCharacters(in: .whitespacesAndNewlines)),
            let rawKey,
            !rawKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }
        return SupabaseConfig(url: url, apiKey: rawKey.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

struct RemoteEventBundle: Sendable {
    let event: EventSummary
    let appData: AppData
    let scores: [RemoteScoreRow]
    let feedback: [RemoteFeedbackRow]
    let penalties: [RemotePenaltyRow]
    let favorites: [RemoteFavoriteRow]
    let specialAwards: [RemoteSpecialAwardRow]
}

struct RemoteRoutineJudgingData: Sendable {
    let scores: [RemoteScoreRow]
    let feedback: [RemoteFeedbackRow]
    let penalties: [RemotePenaltyRow]
}

struct RemoteScoreRow: Codable, Hashable, Sendable {
    let eventID: String
    let routineID: String
    let judgeID: String
    let criterionID: Int
    let value: Double

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case routineID = "routine_id"
        case judgeID = "judge_id"
        case criterionID = "criterion_id"
        case value
    }
}

struct RemoteFeedbackRow: Codable, Hashable, Sendable {
    let eventID: String
    let routineID: String
    let judgeID: String
    let body: String

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case routineID = "routine_id"
        case judgeID = "judge_id"
        case body
    }
}

struct RemotePenaltyRow: Codable, Hashable, Sendable {
    let eventID: String
    let blockID: String
    let routineID: String
    let judgeID: String
    let value: Double

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case blockID = "block_id"
        case routineID = "routine_id"
        case judgeID = "judge_id"
        case value
    }
}

struct RemoteFavoriteRow: Codable, Hashable, Sendable {
    let eventID: String
    let blockID: String
    let routineID: String
    let judgeID: String
    let category: String

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case blockID = "block_id"
        case routineID = "routine_id"
        case judgeID = "judge_id"
        case category
    }
}

struct RemoteSpecialAwardRow: Codable, Hashable, Sendable {
    let eventID: String
    let blockID: String
    let routineID: String?
    let award: String
    let manualValue: String?

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case blockID = "block_id"
        case routineID = "routine_id"
        case award
        case manualValue = "manual_value"
    }
}

struct RemoteJudgeActivityRow: Codable, Hashable, Sendable {
    let eventID: String
    let judgeID: String
    let deviceID: String
    let state: String
    let blockID: String?
    let routineID: String?
    let platform: String?
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case judgeID = "judge_id"
        case deviceID = "device_id"
        case state
        case blockID = "block_id"
        case routineID = "routine_id"
        case platform
        case updatedAt = "updated_at"
    }
}

struct ScoreUpsertRow: Encodable, Sendable {
    let eventID: String
    let routineID: String
    let judgeID: String
    let criterionID: Int
    let value: Double
    let deviceID: String

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case routineID = "routine_id"
        case judgeID = "judge_id"
        case criterionID = "criterion_id"
        case value
        case deviceID = "device_id"
    }
}

struct FeedbackUpsertRow: Encodable, Sendable {
    let eventID: String
    let routineID: String
    let judgeID: String
    let body: String
    let deviceID: String

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case routineID = "routine_id"
        case judgeID = "judge_id"
        case body
        case deviceID = "device_id"
    }
}

struct PenaltyUpsertRow: Encodable, Sendable {
    let eventID: String
    let blockID: String
    let routineID: String
    let judgeID: String
    let value: Double
    let deviceID: String

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case blockID = "block_id"
        case routineID = "routine_id"
        case judgeID = "judge_id"
        case value
        case deviceID = "device_id"
    }
}

struct FavoriteUpsertRow: Encodable, Sendable {
    let eventID: String
    let blockID: String
    let routineID: String
    let judgeID: String
    let category: String
    let deviceID: String

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case blockID = "block_id"
        case routineID = "routine_id"
        case judgeID = "judge_id"
        case category
        case deviceID = "device_id"
    }
}

struct FavoriteDeleteRow: Sendable {
    let eventID: String
    let blockID: String
    let judgeID: String
    let category: String
}

struct SpecialAwardUpsertRow: Encodable, Sendable {
    let eventID: String
    let blockID: String
    let routineID: String?
    let award: String
    let manualValue: String?
    let deviceID: String

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case blockID = "block_id"
        case routineID = "routine_id"
        case award
        case manualValue = "manual_value"
        case deviceID = "device_id"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(eventID, forKey: .eventID)
        try container.encode(blockID, forKey: .blockID)
        if let routineID {
            try container.encode(routineID, forKey: .routineID)
        } else {
            try container.encodeNil(forKey: .routineID)
        }
        try container.encode(award, forKey: .award)
        if let manualValue {
            try container.encode(manualValue, forKey: .manualValue)
        } else {
            try container.encodeNil(forKey: .manualValue)
        }
        try container.encode(deviceID, forKey: .deviceID)
    }
}

struct SpecialAwardDeleteRow: Sendable {
    let eventID: String
    let blockID: String
    let award: String
}

struct JudgeActivityUpsertRow: Encodable, Sendable {
    let eventID: String
    let judgeID: String
    let deviceID: String
    let state: String
    let blockID: String?
    let routineID: String?
    let platform: String

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case judgeID = "judge_id"
        case deviceID = "device_id"
        case state
        case blockID = "block_id"
        case routineID = "routine_id"
        case platform
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(eventID, forKey: .eventID)
        try container.encode(judgeID, forKey: .judgeID)
        try container.encode(deviceID, forKey: .deviceID)
        try container.encode(state, forKey: .state)
        if let blockID {
            try container.encode(blockID, forKey: .blockID)
        } else {
            try container.encodeNil(forKey: .blockID)
        }
        if let routineID {
            try container.encode(routineID, forKey: .routineID)
        } else {
            try container.encodeNil(forKey: .routineID)
        }
        try container.encode(platform, forKey: .platform)
    }
}

struct ExcelImportUploadRow: Encodable, Sendable {
    let eventSlug: String
    let eventName: String
    let filename: String
    let fileSize: Int
    let payloadBase64: String
    let deviceID: String

    enum CodingKeys: String, CodingKey {
        case eventSlug = "event_slug"
        case eventName = "event_name"
        case filename
        case fileSize = "file_size"
        case payloadBase64 = "payload_base64"
        case deviceID = "device_id"
    }
}

struct ExcelImportResponse: Decodable, Sendable {
    let eventID: String
    let eventSlug: String
    let eventName: String
    let routines: Int
    let blocks: Int
    let templates: Int

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case eventSlug = "event_slug"
        case eventName = "event_name"
        case routines
        case blocks
        case templates
    }
}

struct EventArchiveRequest: Encodable, Sendable {
    let eventID: String

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
    }
}

struct EventArchiveResponse: Decodable, Sendable {
    let eventID: String
    let eventName: String
    let archived: Bool

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case eventName = "event_name"
        case archived
    }
}

struct RoutineDeleteRequest: Encodable, Sendable {
    let eventID: String
    let routineID: String

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case routineID = "routine_id"
    }
}

struct RoutineDeleteResponse: Decodable, Sendable {
    let eventID: String
    let routineID: String
    let routineName: String
    let deleted: Bool

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case routineID = "routine_id"
        case routineName = "routine_name"
        case deleted
    }
}

struct RoutineUpdateRequest: Encodable, Sendable {
    let eventID: String
    let routineID: String
    let division: String
    let genre: String
    let level: String
    let category: String

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case routineID = "routine_id"
        case division
        case genre
        case level
        case category
    }
}

struct RoutineUpdateResponse: Decodable, Sendable {
    let eventID: String
    let routineID: String
    let routineName: String
    let division: String?
    let genre: String?
    let level: String?
    let category: String?
    let updated: Bool

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case routineID = "routine_id"
        case routineName = "routine_name"
        case division
        case genre
        case level
        case category
        case updated
    }
}

struct JudgeUpsertRequest: Encodable, Sendable {
    let eventID: String
    let judgeID: String
    let name: String
    let role: String
    let heroImageName: String

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case judgeID = "judge_id"
        case name
        case role
        case heroImageName = "hero_image_name"
    }
}

struct JudgeUpsertResponse: Decodable, Sendable {
    let eventID: String
    let judgeID: String
    let judgeName: String
    let role: String
    let saved: Bool

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case judgeID = "judge_id"
        case judgeName = "judge_name"
        case role
        case saved
    }
}

struct JudgeDeleteRequest: Encodable, Sendable {
    let eventID: String
    let judgeID: String

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case judgeID = "judge_id"
    }
}

struct JudgeDeleteResponse: Decodable, Sendable {
    let eventID: String
    let judgeID: String
    let judgeName: String
    let deleted: Bool

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case judgeID = "judge_id"
        case judgeName = "judge_name"
        case deleted
    }
}

actor RemoteJudgingRepository {
    private let config: SupabaseConfig
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(config: SupabaseConfig) {
        self.config = config
    }

    func fetchEvents() async throws -> [EventSummary] {
        let start = LoadDiagnostics.start()
        LoadDiagnostics.log("fetchEvents started")
        do {
            let rows: [EventRow] = try await get(
                "events?select=id,slug,name,source_name,is_active,event_type&or=(event_type.is.null,event_type.eq.event)&order=is_active.desc,created_at.desc"
            )
            let events = rows.map(\.summary)
            LoadDiagnostics.log("fetchEvents finished events=\(events.count) elapsed=\(LoadDiagnostics.elapsed(since: start))")
            return events
        } catch {
            LoadDiagnostics.log("fetchEvents primary query failed elapsed=\(LoadDiagnostics.elapsed(since: start)) error=\(error.localizedDescription)")
            let rows: [EventRow] = try await get(
                "events?select=id,slug,name,source_name,is_active&order=is_active.desc,created_at.desc"
            )
            let events = rows
                .filter { $0.eventType != "legacy_block" && $0.eventType != "archived" }
                .map(\.summary)
            LoadDiagnostics.log("fetchEvents fallback finished events=\(events.count) elapsed=\(LoadDiagnostics.elapsed(since: start))")
            return events
        }
    }

    func fetchEventBundle(eventID: String) async throws -> RemoteEventBundle {
        let start = LoadDiagnostics.start()
        LoadDiagnostics.log("fetchEventBundle started eventID=\(eventID)")
        let encodedEventID = eventID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? eventID
        let eventRows: [EventRow] = try await get(
            "events?select=id,slug,name,source_name,is_active&id=eq.\(encodedEventID)&limit=1"
        )
        guard let event = eventRows.first?.summary else {
            LoadDiagnostics.log("fetchEventBundle missing event eventID=\(eventID) elapsed=\(LoadDiagnostics.elapsed(since: start))")
            throw RemoteJudgingError.missingEvent
        }
        LoadDiagnostics.log("fetchEventBundle event loaded name=\"\(event.name)\" elapsed=\(LoadDiagnostics.elapsed(since: start))")

        async let blocks: [BlockRow] = fetchBlocks(eventID: encodedEventID)
        async let routines: [RoutineRow] = getAll("routines?select=*&event_id=eq.\(encodedEventID)&order=sort_order.asc")
        async let judges: [JudgeRow] = get("judges?select=*&event_id=eq.\(encodedEventID)&order=sort_order.asc")
        async let templates: [TemplateRow] = get("criteria_templates?select=*&event_id=eq.\(encodedEventID)&order=sort_order.asc")
        async let criteria: [CriterionRowDTO] = getAll("criteria?select=*&event_id=eq.\(encodedEventID)&order=sort_order.asc")
        async let scores: [RemoteScoreRow] = getAll("scores?select=*&event_id=eq.\(encodedEventID)&order=routine_id.asc,judge_id.asc,criterion_id.asc")
        async let feedback: [RemoteFeedbackRow] = getAll("feedback?select=*&event_id=eq.\(encodedEventID)&order=routine_id.asc,judge_id.asc")
        async let penalties: [RemotePenaltyRow] = fetchPenalties(eventID: encodedEventID)
        async let favorites: [RemoteFavoriteRow] = fetchFavorites(eventID: encodedEventID)
        async let specialAwards: [RemoteSpecialAwardRow] = fetchSpecialAwards(eventID: encodedEventID)

        let blockRows = try await blocks
        let routineRows = try await routines
        let judgeRows = try await judges
        let templateRows = try await templates
        let criterionRows = try await criteria
        let scoreRows = try await scores
        let feedbackRows = try await feedback
        let penaltyRows = try await penalties
        let favoriteRows = try await favorites
        let specialAwardRows = try await specialAwards
        LoadDiagnostics.log(
            "fetchEventBundle rows blocks=\(blockRows.count) routines=\(routineRows.count) judges=\(judgeRows.count) templates=\(templateRows.count) criteria=\(criterionRows.count) scores=\(scoreRows.count) feedback=\(feedbackRows.count) penalties=\(penaltyRows.count) favorites=\(favoriteRows.count) specialAwards=\(specialAwardRows.count) elapsed=\(LoadDiagnostics.elapsed(since: start))"
        )

        let criteriaByTemplate = Dictionary(grouping: criterionRows, by: \.templateID)
        let judgingTemplates = templateRows.map { template in
            JudgingTemplate(
                genre: template.genre,
                title: template.title,
                maxScore: template.maxScore,
                criteria: (criteriaByTemplate[template.templateID] ?? []).map(\.criterion)
            )
        }
        let appRoutines = routineRows.map(\.routine)
        let routinesByBlockID = Dictionary(grouping: routineRows) { row in
            let blockID = row.blockID ?? ""
            return blockID.isEmpty ? row.block.stableRemoteID : blockID
        }
        let remoteBlocks = blockRows.map { block in
            let rows = (routinesByBlockID[block.blockID] ?? [])
                .sorted { $0.sortOrder < $1.sortOrder }
            return DanceBlock(
                blockID: block.blockID,
                name: block.name,
                title: block.title,
                sortOrder: block.sortOrder,
                isActive: block.isActive,
                routines: rows.map(\.routine)
            )
        }
        let fallbackBlocks = Dictionary(grouping: routineRows, by: \.block)
            .map { block, rows in
                let sortedRows = rows.sorted { $0.sortOrder < $1.sortOrder }
                return DanceBlock(
                    blockID: sortedRows.first?.blockID,
                    name: block,
                    title: sortedRows.first?.blockTitle ?? "",
                    sortOrder: sortedRows.first?.sortOrder,
                    isActive: nil,
                    routines: sortedRows.map(\.routine)
                )
            }
            .sorted { lhs, rhs in
                (lhs.sortOrder ?? 0) < (rhs.sortOrder ?? 0)
            }

        let appData = AppData(
            sourceName: event.sourceName.isEmpty ? event.name : event.sourceName,
            blocks: remoteBlocks.isEmpty ? fallbackBlocks : remoteBlocks,
            routines: appRoutines,
            templates: judgingTemplates,
            judges: judgeRows.map(\.name),
            judgeProfiles: judgeRows.map(\.profile)
        )
        LoadDiagnostics.log("fetchEventBundle built AppData elapsed=\(LoadDiagnostics.elapsed(since: start))")
        return RemoteEventBundle(event: event, appData: appData, scores: scoreRows, feedback: feedbackRows, penalties: penaltyRows, favorites: favoriteRows, specialAwards: specialAwardRows)
    }

    func upsertScores(_ rows: [ScoreUpsertRow]) async throws {
        try await post(
            "scores?on_conflict=event_id,routine_id,judge_id,criterion_id",
            rows,
            prefer: "resolution=merge-duplicates,return=minimal"
        )
    }

    func fetchRoutineJudgingData(eventID: String, routineID: String, judgeID: String) async throws -> RemoteRoutineJudgingData {
        let encodedEventID = Self.queryValue(eventID)
        let encodedRoutineID = Self.queryValue(routineID)
        let encodedJudgeID = Self.queryValue(judgeID)

        async let scores: [RemoteScoreRow] = getAll(
            "scores?select=event_id,routine_id,judge_id,criterion_id,value&event_id=eq.\(encodedEventID)&routine_id=eq.\(encodedRoutineID)&judge_id=eq.\(encodedJudgeID)&order=criterion_id.asc"
        )
        async let feedback: [RemoteFeedbackRow] = getAll(
            "feedback?select=event_id,routine_id,judge_id,body&event_id=eq.\(encodedEventID)&routine_id=eq.\(encodedRoutineID)&judge_id=eq.\(encodedJudgeID)"
        )
        async let penalties: [RemotePenaltyRow] = getAll(
            "penalties?select=event_id,block_id,routine_id,judge_id,value&event_id=eq.\(encodedEventID)&routine_id=eq.\(encodedRoutineID)&judge_id=eq.\(encodedJudgeID)"
        )

        return try await RemoteRoutineJudgingData(scores: scores, feedback: feedback, penalties: penalties)
    }

    func upsertFeedback(_ rows: [FeedbackUpsertRow]) async throws {
        try await post(
            "feedback?on_conflict=event_id,routine_id,judge_id",
            rows,
            prefer: "resolution=merge-duplicates,return=minimal"
        )
    }

    func upsertPenalties(_ rows: [PenaltyUpsertRow]) async throws {
        try await post(
            "penalties?on_conflict=event_id,routine_id,judge_id",
            rows,
            prefer: "resolution=merge-duplicates,return=minimal"
        )
    }

    func upsertFavorites(_ rows: [FavoriteUpsertRow]) async throws {
        try await post(
            "routine_favorites?on_conflict=event_id,block_id,judge_id,category",
            rows,
            prefer: "resolution=merge-duplicates,return=minimal"
        )
    }

    func deleteFavorites(_ rows: [FavoriteDeleteRow]) async throws {
        for row in rows {
            try await delete(
                "routine_favorites?event_id=eq.\(Self.queryValue(row.eventID))&block_id=eq.\(Self.queryValue(row.blockID))&judge_id=eq.\(Self.queryValue(row.judgeID))&category=eq.\(Self.queryValue(row.category))",
                prefer: "return=minimal"
            )
        }
    }

    func upsertSpecialAward(_ row: SpecialAwardUpsertRow) async throws {
        try await post(
            "special_awards?on_conflict=event_id,block_id,award",
            row,
            prefer: "resolution=merge-duplicates,return=minimal"
        )
    }

    func deleteSpecialAward(_ row: SpecialAwardDeleteRow) async throws {
        try await delete(
            "special_awards?event_id=eq.\(Self.queryValue(row.eventID))&block_id=eq.\(Self.queryValue(row.blockID))&award=eq.\(Self.queryValue(row.award))",
            prefer: "return=minimal"
        )
    }

    func fetchJudgeActivity(eventID: String) async throws -> [RemoteJudgeActivityRow] {
        let encodedEventID = Self.queryValue(eventID)
        return try await getAll(
            "judge_activity?select=*&event_id=eq.\(encodedEventID)&order=updated_at.desc"
        )
    }

    func upsertJudgeActivity(_ row: JudgeActivityUpsertRow) async throws {
        try await post(
            "judge_activity?on_conflict=event_id,judge_id,device_id",
            row,
            prefer: "resolution=merge-duplicates,return=minimal"
        )
    }

    func importExcel(_ row: ExcelImportUploadRow, importSecret: String) async throws -> ExcelImportResponse {
        let data = try encoder.encode(row)
        let response = try await functionRequest(name: "import-excel", body: data, importSecret: importSecret)
        return try decoder.decode(ExcelImportResponse.self, from: response)
    }

    func archiveEvent(eventID: String) async throws -> EventArchiveResponse {
        let data = try encoder.encode(EventArchiveRequest(eventID: eventID))
        let response = try await functionRequest(name: "archive-event", body: data)
        return try decoder.decode(EventArchiveResponse.self, from: response)
    }

    func deleteRoutine(eventID: String, routineID: String, importSecret: String) async throws -> RoutineDeleteResponse {
        let data = try encoder.encode(RoutineDeleteRequest(eventID: eventID, routineID: routineID))
        let response = try await functionRequest(name: "delete-routine", body: data, importSecret: importSecret)
        return try decoder.decode(RoutineDeleteResponse.self, from: response)
    }

    func updateRoutineMetadata(
        eventID: String,
        routineID: String,
        division: String,
        genre: String,
        level: String,
        category: String
    ) async throws -> RoutineUpdateResponse {
        let data = try encoder.encode(
            RoutineUpdateRequest(
                eventID: eventID,
                routineID: routineID,
                division: division,
                genre: genre,
                level: level,
                category: category
            )
        )
        let response = try await functionRequest(name: "update-routine", body: data)
        return try decoder.decode(RoutineUpdateResponse.self, from: response)
    }

    func updateRoutineLevel(eventID: String, routineID: String, routine: Routine, level: String) async throws -> RoutineUpdateResponse {
        let data = try encoder.encode(
            RoutineUpdateRequest(
                eventID: eventID,
                routineID: routineID,
                division: routine.division,
                genre: routine.genre,
                level: level,
                category: routine.category
            )
        )
        let response = try await functionRequest(name: "update-routine", body: data)
        return try decoder.decode(RoutineUpdateResponse.self, from: response)
    }

    func upsertJudge(eventID: String, judgeID: String, name: String, role: UserRole, heroImageName: String = "") async throws -> JudgeUpsertResponse {
        let data = try encoder.encode(
            JudgeUpsertRequest(
                eventID: eventID,
                judgeID: judgeID,
                name: name,
                role: role.rawValue,
                heroImageName: heroImageName
            )
        )
        let response = try await functionRequest(name: "upsert-judge", body: data)
        return try decoder.decode(JudgeUpsertResponse.self, from: response)
    }

    func deleteJudge(eventID: String, judgeID: String) async throws -> JudgeDeleteResponse {
        let data = try encoder.encode(JudgeDeleteRequest(eventID: eventID, judgeID: judgeID))
        let response = try await functionRequest(name: "delete-judge", body: data)
        return try decoder.decode(JudgeDeleteResponse.self, from: response)
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let start = LoadDiagnostics.start()
        let data = try await request(path: path, method: "GET")
        let value = try decoder.decode(T.self, from: data)
        LoadDiagnostics.log("GET \(LoadDiagnostics.tableName(from: path)) decoded bytes=\(data.count) elapsed=\(LoadDiagnostics.elapsed(since: start))")
        return value
    }

    private func getAll<T: Decodable>(_ path: String, pageSize: Int = 1000) async throws -> [T] {
        let overallStart = LoadDiagnostics.start()
        let tableName = LoadDiagnostics.tableName(from: path)
        LoadDiagnostics.log("GET \(tableName) paginated started pageSize=\(pageSize)")
        var rows: [T] = []
        var start = 0

        while true {
            let end = start + pageSize - 1
            let pageStart = LoadDiagnostics.start()
            let data = try await request(path: path, method: "GET", range: "\(start)-\(end)")
            let page = try decoder.decode([T].self, from: data)
            rows.append(contentsOf: page)
            LoadDiagnostics.log("GET \(tableName) page range=\(start)-\(end) rows=\(page.count) total=\(rows.count) bytes=\(data.count) elapsed=\(LoadDiagnostics.elapsed(since: pageStart))")

            guard page.count == pageSize else {
                LoadDiagnostics.log("GET \(tableName) paginated finished rows=\(rows.count) elapsed=\(LoadDiagnostics.elapsed(since: overallStart))")
                return rows
            }
            start += pageSize
        }
    }

    private func fetchBlocks(eventID: String) async throws -> [BlockRow] {
        do {
            return try await getAll("blocks?select=*&event_id=eq.\(eventID)&order=sort_order.asc")
        } catch {
            return []
        }
    }

    private func fetchFavorites(eventID: String) async throws -> [RemoteFavoriteRow] {
        do {
            return try await getAll("routine_favorites?select=*&event_id=eq.\(eventID)&order=block_id.asc,judge_id.asc,category.asc")
        } catch {
            return []
        }
    }

    private func fetchPenalties(eventID: String) async throws -> [RemotePenaltyRow] {
        do {
            return try await getAll("penalties?select=*&event_id=eq.\(eventID)&order=routine_id.asc,judge_id.asc")
        } catch {
            return []
        }
    }

    private func fetchSpecialAwards(eventID: String) async throws -> [RemoteSpecialAwardRow] {
        do {
            return try await getAll("special_awards?select=*&event_id=eq.\(eventID)&order=block_id.asc,award.asc")
        } catch {
            return []
        }
    }

    private func post<T: Encodable>(_ path: String, _ body: T, prefer: String) async throws {
        let data = try encoder.encode(body)
        _ = try await request(path: path, method: "POST", body: data, prefer: prefer)
    }

    private func delete(_ path: String, prefer: String) async throws {
        _ = try await request(path: path, method: "DELETE", prefer: prefer)
    }

    private static func queryValue(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
    }

    private func request(path: String, method: String, body: Data? = nil, prefer: String? = nil, range: String? = nil) async throws -> Data {
        guard let endpoint = URL(string: "\(config.url.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/rest/v1/\(path)") else {
            throw RemoteJudgingError.invalidURL
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = method
        request.httpBody = body
        request.setValue(config.apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let prefer {
            request.setValue(prefer, forHTTPHeaderField: "Prefer")
        }
        if let range {
            request.setValue(range, forHTTPHeaderField: "Range")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw RemoteJudgingError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let detail = String(data: data, encoding: .utf8) ?? "sin detalle"
            throw RemoteJudgingError.http(status: http.statusCode, detail: detail)
        }
        return data.isEmpty ? Data("null".utf8) : data
    }

    private func functionRequest(name: String, body: Data, importSecret: String? = nil) async throws -> Data {
        guard let endpoint = URL(string: "\(config.url.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/functions/v1/\(name)") else {
            throw RemoteJudgingError.invalidURL
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue(config.apiKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let cleanImportSecret = importSecret?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !cleanImportSecret.isEmpty {
            request.setValue(cleanImportSecret, forHTTPHeaderField: "x-import-secret")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw RemoteJudgingError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let detail = String(data: data, encoding: .utf8) ?? "sin detalle"
            throw RemoteJudgingError.http(status: http.statusCode, detail: detail)
        }
        return data.isEmpty ? Data("null".utf8) : data
    }
}

enum RemoteJudgingError: LocalizedError {
    case invalidURL
    case invalidResponse
    case missingEvent
    case http(status: Int, detail: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "URL de Supabase inválida."
        case .invalidResponse:
            "Respuesta inválida de Supabase."
        case .missingEvent:
            "No se encontro el evento solicitado."
        case let .http(status, detail):
            "Supabase respondio \(status): \(Self.cleanHTTPDetail(detail))"
        }
    }

    private static func cleanHTTPDetail(_ detail: String) -> String {
        guard let data = detail.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return detail
        }
        for key in ["error", "message", "details", "hint"] {
            if let value = object[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        return detail
    }
}

private struct EventRow: Codable, Sendable {
    let id: String
    let slug: String
    let name: String
    let sourceName: String
    let isActive: Bool
    let eventType: String?

    var summary: EventSummary {
        EventSummary(id: id, slug: slug, name: name, sourceName: sourceName, isActive: isActive, eventType: eventType)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case slug
        case name
        case sourceName = "source_name"
        case isActive = "is_active"
        case eventType = "event_type"
    }
}

private struct BlockRow: Codable, Sendable {
    let blockID: String
    let name: String
    let title: String
    let sortOrder: Int
    let isActive: Bool

    enum CodingKeys: String, CodingKey {
        case blockID = "block_id"
        case name
        case title
        case sortOrder = "sort_order"
        case isActive = "is_active"
    }
}

private struct RoutineRow: Codable, Sendable {
    let eventID: String
    let routineID: String
    let blockID: String?
    let block: String
    let blockTitle: String
    let sortOrder: Int
    let name: String
    let academy: String
    let division: String
    let genre: String
    let level: String
    let category: String
    let choreographer: String
    let participant: String?
    let state: String
    let scheduledTime: String
    let duration: String

    var routine: Routine {
        Routine(
            id: routineID,
            blockID: blockID,
            block: block,
            name: name,
            academy: academy,
            division: division,
            genre: genre,
            level: level,
            category: category,
            choreographer: choreographer,
            participant: participant,
            state: state,
            time: scheduledTime,
            duration: duration
        )
    }

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case routineID = "routine_id"
        case blockID = "block_id"
        case block
        case blockTitle = "block_title"
        case sortOrder = "sort_order"
        case name
        case academy
        case division
        case genre
        case level
        case category
        case choreographer
        case participant
        case state
        case scheduledTime = "scheduled_time"
        case duration
    }
}

private struct JudgeRow: Codable, Sendable {
    let judgeID: String
    let name: String
    let role: String?
    let heroImageName: String?

    var profile: JudgeProfile {
        JudgeProfile(
            judgeID: judgeID,
            name: name,
            role: UserRole(rawValue: role ?? "") ?? (judgeID == "ati" ? .admin : .judge),
            heroImageName: heroImageName
        )
    }

    enum CodingKeys: String, CodingKey {
        case judgeID = "judge_id"
        case name
        case role
        case heroImageName = "hero_image_name"
    }
}

private struct TemplateRow: Codable, Sendable {
    let templateID: String
    let genre: String
    let title: String
    let maxScore: Double

    enum CodingKeys: String, CodingKey {
        case templateID = "template_id"
        case genre
        case title
        case maxScore = "max_score"
    }
}

private struct CriterionRowDTO: Codable, Sendable {
    let templateID: String
    let criterionID: Int
    let section: String
    let label: String
    let maxScore: Double

    var criterion: Criterion {
        Criterion(id: criterionID, section: section, label: label, maxScore: maxScore)
    }

    enum CodingKeys: String, CodingKey {
        case templateID = "template_id"
        case criterionID = "criterion_id"
        case section
        case label
        case maxScore = "max_score"
    }
}
