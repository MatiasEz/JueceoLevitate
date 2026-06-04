import Foundation
import JueceoCore

enum JudgingSheetMailStatus: Equatable {
    case idle
    case sending
    case completed(Int)
    case failed(String)

    var title: String {
        switch self {
        case .idle:
            "Mail listo"
        case .sending:
            "Enviando mails"
        case let .completed(count):
            "\(count) mails enviados"
        case .failed:
            "Error en mail"
        }
    }

    var systemImage: String {
        switch self {
        case .idle:
            "paperplane"
        case .sending:
            "arrow.triangle.2.circlepath"
        case .completed:
            "paperplane.fill"
        case .failed:
            "exclamationmark.triangle"
        }
    }

    var isSending: Bool {
        if case .sending = self {
            return true
        }
        return false
    }
}

struct AcademyMailRecipient: Decodable, Equatable, Sendable {
    let academy: String
    let email: String

    var cleanEmail: String? {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.contains("@") else { return nil }
        return trimmed
    }

    var normalizedAcademyKey: String { academy.normalizedKey }
}

struct JudgingSheetMailConfig: Sendable {
    let scriptURL: URL
    let sharedSecret: String?

    static func load(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> JudgingSheetMailConfig? {
        let rawScriptURL = environment["JUDGING_MAIL_SCRIPT_URL"]
            ?? bundle.object(forInfoDictionaryKey: "JUDGING_MAIL_SCRIPT_URL") as? String
        let rawSharedSecret = environment["JUDGING_MAIL_SHARED_SECRET"]
            ?? bundle.object(forInfoDictionaryKey: "JUDGING_MAIL_SHARED_SECRET") as? String

        guard
            let scriptURLText = clean(rawScriptURL),
            let scriptURL = URL(string: scriptURLText),
            scriptURL.scheme == "https" || scriptURL.scheme == "http"
        else {
            return nil
        }

        return JudgingSheetMailConfig(
            scriptURL: scriptURL,
            sharedSecret: clean(rawSharedSecret)
        )
    }

    private static func clean(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              !trimmed.contains("$(")
        else {
            return nil
        }
        return trimmed
    }
}

enum JudgingSheetMailServiceError: LocalizedError {
    case missingRecipientsFile
    case missingLinks
    case missingEmails([String])
    case invalidResponse
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingRecipientsFile:
            "Completá academy_emails.json con los mails de cada academia."
        case .missingLinks:
            "No hay links válidos de Drive para enviar."
        case let .missingEmails(academies):
            "Faltan mails para: \(Self.academyList(academies))."
        case .invalidResponse:
            "Apps Script devolvió una respuesta inválida."
        case let .requestFailed(message):
            message
        }
    }

    private static func academyList(_ academies: [String]) -> String {
        let visibleAcademies = academies.prefix(6).joined(separator: ", ")
        let remainingCount = max(0, academies.count - 6)
        guard remainingCount > 0 else { return visibleAcademies }
        return "\(visibleAcademies) y \(remainingCount) más"
    }
}

struct JudgingSheetMailPayload: Encodable, Sendable {
    let sharedSecret: String?
    let eventName: String
    let blockName: String
    let subject: String
    let bodyIntro: String
    let bodyClosing: String
    let grantDriveAccess: Bool
    let academies: [AcademyJudgingSheetMail]
}

struct AcademyJudgingSheetMail: Encodable, Sendable {
    let academy: String
    let email: String
    let links: [JudgingSheetDriveLink]
}

struct JudgingSheetDriveLink: Encodable, Sendable {
    let fileID: String
    let fileName: String
    let routineID: String
    let routineName: String
    let judge: String
    let url: String
}

struct JudgingSheetMailResponse: Decodable, Sendable {
    let ok: Bool?
    let sent: Int?
    let skipped: Int?
    let message: String?
    let warnings: [String]?
    let errors: [String]?

    var hasWarnings: Bool {
        (skipped ?? 0) > 0 || !(warnings ?? []).isEmpty || !(errors ?? []).isEmpty
    }
}

final class JudgingSheetMailService {
    static let defaultRecipientEmail = "matialeezcurra@gmail.com"
    static let subject = "Tu devolución de jueceo ya está disponible"

    static let bodyIntro = """
    Queremos compartirles las hojas de jueceo correspondientes a su participación. En ellas van a encontrar el detalle de las evaluaciones, observaciones y puntajes registrados durante la competencia.

    Más allá del resultado, estas hojas están pensadas como una herramienta de crecimiento: una mirada técnica para revisar el trabajo realizado, reconocer fortalezas y seguir puliendo cada presentación de cara a lo que viene.
    """

    static let bodyClosing = """
    Gracias por ser parte y por poner tanta dedicación en cada pasada.
    Nos alegra acompañar el proceso de cada academia y seguir construyendo juntos un espacio de evaluación cada vez más claro, justo y útil.

    Saludos,
    Equipo Jueceo
    """

    private let config: JudgingSheetMailConfig

    init(config: JudgingSheetMailConfig) {
        self.config = config
    }

    static func loadRecipients(bundle: Bundle = .main) -> [AcademyMailRecipient] {
        guard let url = bundle.url(forResource: "academy_emails", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let recipients = try? JSONDecoder().decode([AcademyMailRecipient].self, from: data)
        else {
            return []
        }
        return recipients
    }

    func makePayload(
        eventName: String,
        blockName: String,
        summary: GoogleDriveExportSummary,
        recipients: [AcademyMailRecipient]
    ) throws -> JudgingSheetMailPayload {
        let linkedSheets = summary.judgingSheets.filter { sheet in
            guard let link = sheet.webViewLink?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                return false
            }
            return !link.isEmpty
        }
        guard !linkedSheets.isEmpty else {
            throw JudgingSheetMailServiceError.missingLinks
        }

        let sheetsByAcademy = Dictionary(grouping: linkedSheets) { $0.academy.normalizedKey }
        let recipientsByAcademy = Dictionary(grouping: recipients) { $0.normalizedAcademyKey }
        var academyPayloads: [AcademyJudgingSheetMail] = []

        for academyKey in sheetsByAcademy.keys.sorted(by: academyNameSort(sheetsByAcademy: sheetsByAcademy)) {
            guard let sheets = sheetsByAcademy[academyKey], let academyName = sheets.first?.academy else {
                continue
            }

            let email = recipientsByAcademy[academyKey]?.first(where: { $0.cleanEmail != nil })?.cleanEmail
                ?? Self.defaultRecipientEmail

            let links = sheets
                .sorted(by: judgingSheetSort)
                .compactMap { sheet -> JudgingSheetDriveLink? in
                    guard let url = sheet.webViewLink?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty else {
                        return nil
                    }
                    return JudgingSheetDriveLink(
                        fileID: sheet.fileID,
                        fileName: sheet.fileName,
                        routineID: sheet.routineID,
                        routineName: sheet.routineName,
                        judge: sheet.judge,
                        url: url
                    )
                }

            guard !links.isEmpty else { continue }
            academyPayloads.append(AcademyJudgingSheetMail(academy: academyName, email: email, links: links))
        }

        guard !academyPayloads.isEmpty else {
            throw JudgingSheetMailServiceError.missingLinks
        }

        return JudgingSheetMailPayload(
            sharedSecret: config.sharedSecret,
            eventName: eventName,
            blockName: blockName,
            subject: Self.subject,
            bodyIntro: Self.bodyIntro,
            bodyClosing: Self.bodyClosing,
            grantDriveAccess: true,
            academies: academyPayloads
        )
    }

    func send(_ payload: JudgingSheetMailPayload) async throws -> JudgingSheetMailResponse {
        var request = URLRequest(url: config.scriptURL)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw JudgingSheetMailServiceError.invalidResponse
        }

        let decodedResponse = try? JSONDecoder().decode(JudgingSheetMailResponse.self, from: data)
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = decodedResponse?.message
                ?? Self.responseMessage(from: data, statusCode: httpResponse.statusCode)
            throw JudgingSheetMailServiceError.requestFailed(message)
        }

        guard let decodedResponse else {
            throw JudgingSheetMailServiceError.requestFailed(
                Self.responseMessage(from: data, statusCode: httpResponse.statusCode)
            )
        }

        if decodedResponse.ok == false {
            if (decodedResponse.sent ?? 0) > 0 {
                return decodedResponse
            }
            let message = decodedResponse.message
                ?? decodedResponse.errors?.joined(separator: "\n")
                ?? "Apps Script no pudo enviar los mails."
            throw JudgingSheetMailServiceError.requestFailed(message)
        }

        return decodedResponse
    }

    private static func responseMessage(from data: Data, statusCode: Int) -> String {
        let fallback = HTTPURLResponse.localizedString(forStatusCode: statusCode)
        guard let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty
        else {
            return fallback
        }

        let lowercasedText = text.lowercased()
        guard lowercasedText.contains("<!doctype html") || lowercasedText.contains("<html") else {
            return text
        }

        if statusCode == 401 || statusCode == 403 || lowercasedText.contains("no se encontró la página") || lowercasedText.contains("no se pudo abrir el archivo") {
            return "Google no dejó abrir el Web App de Apps Script. Volvé a desplegarlo con acceso \"Cualquier persona\" y usá la URL que termina en /exec."
        }
        return "Apps Script devolvió una página HTML en vez de JSON. Revisá la URL del Web App y el despliegue publicado."
    }

    private func academyNameSort(
        sheetsByAcademy: [String: [GoogleDriveJudgingSheetLink]]
    ) -> (String, String) -> Bool {
        { lhs, rhs in
            let lhsName = sheetsByAcademy[lhs]?.first?.academy ?? lhs
            let rhsName = sheetsByAcademy[rhs]?.first?.academy ?? rhs
            return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
        }
    }

    private func judgingSheetSort(_ lhs: GoogleDriveJudgingSheetLink, _ rhs: GoogleDriveJudgingSheetLink) -> Bool {
        let lhsNumber = Int(lhs.routineID) ?? Int.max
        let rhsNumber = Int(rhs.routineID) ?? Int.max
        if lhsNumber != rhsNumber {
            return lhsNumber < rhsNumber
        }
        if lhs.routineName != rhs.routineName {
            return lhs.routineName.localizedCaseInsensitiveCompare(rhs.routineName) == .orderedAscending
        }
        return lhs.judge.localizedCaseInsensitiveCompare(rhs.judge) == .orderedAscending
    }
}
