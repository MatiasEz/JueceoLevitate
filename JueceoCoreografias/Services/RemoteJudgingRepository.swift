import Foundation

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

actor RemoteJudgingRepository {
    private let config: SupabaseConfig
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(config: SupabaseConfig) {
        self.config = config
    }

    func fetchEvents() async throws -> [EventSummary] {
        let rows: [EventRow] = try await get(
            "events?select=id,slug,name,source_name,is_active&order=is_active.desc,created_at.desc"
        )
        return rows.map(\.summary)
    }

    func fetchEventBundle(eventID: String) async throws -> RemoteEventBundle {
        let encodedEventID = eventID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? eventID
        let eventRows: [EventRow] = try await get(
            "events?select=id,slug,name,source_name,is_active&id=eq.\(encodedEventID)&limit=1"
        )
        guard let event = eventRows.first?.summary else {
            throw RemoteJudgingError.missingEvent
        }

        async let routines: [RoutineRow] = get("routines?select=*&event_id=eq.\(encodedEventID)&order=sort_order.asc")
        async let judges: [JudgeRow] = get("judges?select=*&event_id=eq.\(encodedEventID)&order=sort_order.asc")
        async let templates: [TemplateRow] = get("criteria_templates?select=*&event_id=eq.\(encodedEventID)&order=sort_order.asc")
        async let criteria: [CriterionRowDTO] = get("criteria?select=*&event_id=eq.\(encodedEventID)&order=sort_order.asc")
        async let scores: [RemoteScoreRow] = get("scores?select=*&event_id=eq.\(encodedEventID)")
        async let feedback: [RemoteFeedbackRow] = get("feedback?select=*&event_id=eq.\(encodedEventID)")

        let routineRows = try await routines
        let judgeRows = try await judges
        let templateRows = try await templates
        let criterionRows = try await criteria

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
        let blocks = Dictionary(grouping: routineRows, by: \.block)
            .map { block, rows in
                let sortedRows = rows.sorted { $0.sortOrder < $1.sortOrder }
                return DanceBlock(
                    name: block,
                    title: sortedRows.first?.blockTitle ?? "",
                    routines: sortedRows.map(\.routine)
                )
            }
            .sorted { lhs, rhs in
                let left = routineRows.first { $0.block == lhs.name }?.sortOrder ?? 0
                let right = routineRows.first { $0.block == rhs.name }?.sortOrder ?? 0
                return left < right
            }

        let appData = AppData(
            sourceName: event.sourceName.isEmpty ? event.name : event.sourceName,
            blocks: blocks,
            routines: appRoutines,
            templates: judgingTemplates,
            judges: judgeRows.map(\.name)
        )
        return try await RemoteEventBundle(event: event, appData: appData, scores: scores, feedback: feedback)
    }

    func upsertScores(_ rows: [ScoreUpsertRow]) async throws {
        try await post(
            "scores?on_conflict=event_id,routine_id,judge_id,criterion_id",
            rows,
            prefer: "resolution=merge-duplicates,return=minimal"
        )
    }

    func upsertFeedback(_ rows: [FeedbackUpsertRow]) async throws {
        try await post(
            "feedback?on_conflict=event_id,routine_id,judge_id",
            rows,
            prefer: "resolution=merge-duplicates,return=minimal"
        )
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let data = try await request(path: path, method: "GET")
        return try decoder.decode(T.self, from: data)
    }

    private func post<T: Encodable>(_ path: String, _ body: T, prefer: String) async throws {
        let data = try encoder.encode(body)
        _ = try await request(path: path, method: "POST", body: data, prefer: prefer)
    }

    private func request(path: String, method: String, body: Data? = nil, prefer: String? = nil) async throws -> Data {
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
            "URL de Supabase invalida."
        case .invalidResponse:
            "Respuesta invalida de Supabase."
        case .missingEvent:
            "No se encontro el evento solicitado."
        case let .http(status, detail):
            "Supabase respondio \(status): \(detail)"
        }
    }
}

private struct EventRow: Codable, Sendable {
    let id: String
    let slug: String
    let name: String
    let sourceName: String
    let isActive: Bool

    var summary: EventSummary {
        EventSummary(id: id, slug: slug, name: name, sourceName: sourceName, isActive: isActive)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case slug
        case name
        case sourceName = "source_name"
        case isActive = "is_active"
    }
}

private struct RoutineRow: Codable, Sendable {
    let eventID: String
    let routineID: String
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
    let state: String
    let scheduledTime: String
    let duration: String

    var routine: Routine {
        Routine(
            id: routineID,
            block: block,
            name: name,
            academy: academy,
            division: division,
            genre: genre,
            level: level,
            category: category,
            choreographer: choreographer,
            state: state,
            time: scheduledTime,
            duration: duration
        )
    }

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case routineID = "routine_id"
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
        case state
        case scheduledTime = "scheduled_time"
        case duration
    }
}

private struct JudgeRow: Codable, Sendable {
    let judgeID: String
    let name: String

    enum CodingKeys: String, CodingKey {
        case judgeID = "judge_id"
        case name
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
