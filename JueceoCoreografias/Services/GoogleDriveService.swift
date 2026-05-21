import AuthenticationServices
import CryptoKit
import Foundation
import Security
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit
#endif

struct GoogleDriveUploadedFile: Identifiable, Decodable, Sendable {
    let id: String
    let name: String
    let webViewLink: String?
}

struct GoogleDriveExportSummary: Sendable {
    let rootFolderName: String
    let uploadedFiles: [GoogleDriveUploadedFile]
}

enum GoogleDriveServiceError: LocalizedError {
    case missingConfiguration
    case authorizationCancelled
    case invalidCallback
    case missingRefreshToken
    case invalidResponse
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            "Configura GOOGLE_CLIENT_ID y GOOGLE_REVERSED_CLIENT_ID para exportar a Drive."
        case .authorizationCancelled:
            "Inicio de sesion con Google cancelado."
        case .invalidCallback:
            "Google no devolvió un código válido."
        case .missingRefreshToken:
            "No hay sesion de Google guardada. Vuelve a iniciar sesion."
        case .invalidResponse:
            "Google devolvió una respuesta inválida."
        case let .requestFailed(message):
            message
        }
    }
}

@MainActor
final class GoogleDriveService {
    private let config: GoogleDriveConfig
    private let tokenStore = GoogleOAuthTokenStore()
    private let presentationProvider = GoogleOAuthPresentationProvider()
    private var authSession: ASWebAuthenticationSession?

    init(config: GoogleDriveConfig) {
        self.config = config
    }

    static func configured() throws -> GoogleDriveService {
        guard let config = GoogleDriveConfig.load() else {
            throw GoogleDriveServiceError.missingConfiguration
        }
        return GoogleDriveService(config: config)
    }

    var rootFolderName: String { config.rootFolderName }

    func uploadPDF(fileURL: URL, fileName: String, folderPath: [String]) async throws -> GoogleDriveUploadedFile {
        let accessToken = try await validAccessToken()
        let folderID = try await ensureFolderPath(folderPath, accessToken: accessToken)
        return try await upsertPDF(fileURL: fileURL, fileName: fileName, parentFolderID: folderID, accessToken: accessToken)
    }

    private func ensureFolderPath(_ folderPath: [String], accessToken: String) async throws -> String {
        var parentID = "root"
        for folderName in folderPath {
            if let existing = try await findFile(
                named: folderName,
                parentID: parentID,
                mimeType: GoogleDriveMIME.folder,
                accessToken: accessToken
            ) {
                parentID = existing.id
            } else {
                let created = try await createFolder(named: folderName, parentID: parentID, accessToken: accessToken)
                parentID = created.id
            }
        }
        return parentID
    }

    private func validAccessToken() async throws -> String {
        if let token = tokenStore.load(), token.expirationDate > Date().addingTimeInterval(90) {
            return token.accessToken
        }
        if let refreshToken = tokenStore.load()?.refreshToken {
            let refreshed = try await refreshAccessToken(refreshToken: refreshToken)
            tokenStore.save(refreshed)
            return refreshed.accessToken
        }
        let authorized = try await authorize()
        tokenStore.save(authorized)
        return authorized.accessToken
    }

    private func authorize() async throws -> GoogleOAuthToken {
        let verifier = GoogleOAuthHelpers.randomBase64URL(byteCount: 32)
        let challenge = GoogleOAuthHelpers.codeChallenge(for: verifier)
        let state = GoogleOAuthHelpers.randomBase64URL(byteCount: 16)

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: config.clientID),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: GoogleDriveMIME.driveScope),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "include_granted_scopes", value: "true")
        ]
        guard let url = components?.url else {
            throw GoogleDriveServiceError.invalidResponse
        }

        let callbackURL = try await authenticationCallback(for: url, expectedState: state)
        guard
            let callbackComponents = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
            callbackComponents.queryItems?.first(where: { $0.name == "state" })?.value == state,
            let code = callbackComponents.queryItems?.first(where: { $0.name == "code" })?.value
        else {
            throw GoogleDriveServiceError.invalidCallback
        }

        return try await exchangeCodeForToken(code: code, verifier: verifier)
    }

    private func authenticationCallback(for url: URL, expectedState: String) async throws -> URL {
        #if targetEnvironment(macCatalyst)
        return try await GoogleOAuthCallbackCoordinator.shared.beginExternalAuth(
            url: url,
            callbackScheme: config.reversedClientID,
            expectedState: expectedState
        )
        #else
        try await withCheckedThrowingContinuation { continuation in
            let continuationBox = GoogleAuthContinuationBox(continuation)
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: config.reversedClientID
            ) { callbackURL, error in
                if let callbackURL {
                    continuationBox.resume(returning: callbackURL)
                } else if let error = error as? ASWebAuthenticationSessionError,
                          error.code == .canceledLogin {
                    continuationBox.resume(throwing: GoogleDriveServiceError.authorizationCancelled)
                } else {
                    continuationBox.resume(throwing: error ?? GoogleDriveServiceError.invalidCallback)
                }
            }
            session.presentationContextProvider = presentationProvider
            session.prefersEphemeralWebBrowserSession = false
            authSession = session
            if !session.start() {
                continuationBox.resume(throwing: GoogleDriveServiceError.invalidCallback)
            }
        }
        #endif
    }

    private func exchangeCodeForToken(code: String, verifier: String) async throws -> GoogleOAuthToken {
        try await tokenRequest([
            "client_id": config.clientID,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": config.redirectURI
        ])
    }

    private func refreshAccessToken(refreshToken: String) async throws -> GoogleOAuthToken {
        let refreshed = try await tokenRequest([
            "client_id": config.clientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken
        ])
        if refreshed.refreshToken == nil {
            return GoogleOAuthToken(
                accessToken: refreshed.accessToken,
                refreshToken: refreshToken,
                expirationDate: refreshed.expirationDate
            )
        }
        return refreshed
    }

    private func tokenRequest(_ params: [String: String]) async throws -> GoogleOAuthToken {
        guard let url = URL(string: "https://oauth2.googleapis.com/token") else {
            throw GoogleDriveServiceError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = GoogleOAuthHelpers.formEncoded(params).data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        let tokenResponse = try JSONDecoder().decode(GoogleOAuthTokenResponse.self, from: data)
        return GoogleOAuthToken(
            accessToken: tokenResponse.accessToken,
            refreshToken: tokenResponse.refreshToken,
            expirationDate: Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn))
        )
    }

    private func findFile(named name: String, parentID: String, mimeType: String, accessToken: String) async throws -> GoogleDriveUploadedFile? {
        var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files")
        let query = [
            "'\(GoogleDriveHelpers.queryEscaped(parentID))' in parents",
            "name = '\(GoogleDriveHelpers.queryEscaped(name))'",
            "mimeType = '\(mimeType)'",
            "trashed = false"
        ].joined(separator: " and ")
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "spaces", value: "drive"),
            URLQueryItem(name: "fields", value: "files(id,name,webViewLink)"),
            URLQueryItem(name: "pageSize", value: "1")
        ]
        guard let url = components?.url else {
            throw GoogleDriveServiceError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let data = try await authorizedData(for: request)
        let response = try JSONDecoder().decode(GoogleDriveFilesResponse.self, from: data)
        return response.files.first
    }

    private func createFolder(named name: String, parentID: String, accessToken: String) async throws -> GoogleDriveUploadedFile {
        guard let url = URL(string: "https://www.googleapis.com/drive/v3/files?fields=id,name,webViewLink") else {
            throw GoogleDriveServiceError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(GoogleDriveMetadata(name: name, mimeType: GoogleDriveMIME.folder, parents: [parentID]))

        let data = try await authorizedData(for: request)
        return try JSONDecoder().decode(GoogleDriveUploadedFile.self, from: data)
    }

    private func upsertPDF(fileURL: URL, fileName: String, parentFolderID: String, accessToken: String) async throws -> GoogleDriveUploadedFile {
        let existing = try await findFile(named: fileName, parentID: parentFolderID, mimeType: GoogleDriveMIME.pdf, accessToken: accessToken)
        let metadata = GoogleDriveMetadata(
            name: fileName,
            mimeType: GoogleDriveMIME.pdf,
            parents: existing == nil ? [parentFolderID] : nil
        )
        let boundary = "Boundary-\(UUID().uuidString)"
        let body = try GoogleDriveHelpers.multipartBody(
            metadata: metadata,
            fileURL: fileURL,
            mimeType: GoogleDriveMIME.pdf,
            boundary: boundary
        )
        let endpoint: String
        let method: String
        if let existing {
            endpoint = "https://www.googleapis.com/upload/drive/v3/files/\(existing.id)?uploadType=multipart&fields=id,name,webViewLink"
            method = "PATCH"
        } else {
            endpoint = "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id,name,webViewLink"
            method = "POST"
        }
        guard let url = URL(string: endpoint) else {
            throw GoogleDriveServiceError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let data = try await authorizedData(for: request)
        return try JSONDecoder().decode(GoogleDriveUploadedFile.self, from: data)
    }

    private func authorizedData(for request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return data
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GoogleDriveServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = (try? JSONDecoder().decode(GoogleDriveErrorResponse.self, from: data).error.message)
                ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw GoogleDriveServiceError.requestFailed(message)
        }
    }
}

@MainActor
final class GoogleOAuthCallbackCoordinator {
    static let shared = GoogleOAuthCallbackCoordinator()

    private struct PendingAuthorization {
        let callbackScheme: String
        let expectedState: String
        let continuation: CheckedContinuation<URL, Error>
        let timeoutTask: Task<Void, Never>
    }

    private var pendingAuthorization: PendingAuthorization?

    private init() {}

    func beginExternalAuth(url: URL, callbackScheme: String, expectedState: String) async throws -> URL {
        cancelPendingAuthorization()

        return try await withCheckedThrowingContinuation { continuation in
            let timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(300))
                self?.finishPendingAuthorization(throwing: GoogleDriveServiceError.authorizationCancelled)
            }
            pendingAuthorization = PendingAuthorization(
                callbackScheme: callbackScheme,
                expectedState: expectedState,
                continuation: continuation,
                timeoutTask: timeoutTask
            )

            #if canImport(UIKit)
            UIApplication.shared.open(url, options: [:]) { [weak self] success in
                guard !success else { return }
                Task { @MainActor in
                    self?.finishPendingAuthorization(throwing: GoogleDriveServiceError.invalidCallback)
                }
            }
            #elseif canImport(AppKit)
            if !NSWorkspace.shared.open(url) {
                finishPendingAuthorization(throwing: GoogleDriveServiceError.invalidCallback)
            }
            #else
            finishPendingAuthorization(throwing: GoogleDriveServiceError.invalidCallback)
            #endif
        }
    }

    @discardableResult
    func handle(_ url: URL) -> Bool {
        guard let pendingAuthorization,
              url.scheme == pendingAuthorization.callbackScheme
        else {
            return false
        }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            finishPendingAuthorization(throwing: GoogleDriveServiceError.invalidCallback)
            return true
        }

        let queryItems = components.queryItems ?? []
        if let error = queryItems.first(where: { $0.name == "error" })?.value {
            let description = queryItems.first(where: { $0.name == "error_description" })?.value
            finishPendingAuthorization(throwing: GoogleDriveServiceError.requestFailed(description ?? error))
            return true
        }

        guard queryItems.first(where: { $0.name == "state" })?.value == pendingAuthorization.expectedState,
              queryItems.first(where: { $0.name == "code" })?.value != nil
        else {
            finishPendingAuthorization(throwing: GoogleDriveServiceError.invalidCallback)
            return true
        }

        finishPendingAuthorization(returning: url)
        return true
    }

    private func cancelPendingAuthorization() {
        finishPendingAuthorization(throwing: GoogleDriveServiceError.authorizationCancelled)
    }

    private func finishPendingAuthorization(returning url: URL) {
        guard let pendingAuthorization else { return }
        self.pendingAuthorization = nil
        pendingAuthorization.timeoutTask.cancel()
        pendingAuthorization.continuation.resume(returning: url)
    }

    private func finishPendingAuthorization(throwing error: Error) {
        guard let pendingAuthorization else { return }
        self.pendingAuthorization = nil
        pendingAuthorization.timeoutTask.cancel()
        pendingAuthorization.continuation.resume(throwing: error)
    }
}

struct GoogleDriveConfig: Sendable {
    let clientID: String
    let reversedClientID: String
    let rootFolderName: String

    var redirectURI: String { "\(reversedClientID):/oauth2redirect" }

    static func load() -> GoogleDriveConfig? {
        let environment = ProcessInfo.processInfo.environment
        let rawClientID = environment["GOOGLE_CLIENT_ID"]
            ?? Bundle.main.object(forInfoDictionaryKey: "GOOGLE_CLIENT_ID") as? String
        let rawReversedClientID = environment["GOOGLE_REVERSED_CLIENT_ID"]
            ?? Bundle.main.object(forInfoDictionaryKey: "GOOGLE_REVERSED_CLIENT_ID") as? String
        let rootFolder = environment["GOOGLE_DRIVE_ROOT_FOLDER"]
            ?? Bundle.main.object(forInfoDictionaryKey: "GOOGLE_DRIVE_ROOT_FOLDER") as? String
            ?? "Levitate CDMX 2026"

        guard
            let clientID = clean(rawClientID),
            let reversedClientID = clean(rawReversedClientID)
        else {
            return nil
        }
        return GoogleDriveConfig(
            clientID: clientID,
            reversedClientID: reversedClientID,
            rootFolderName: clean(rootFolder) ?? "Levitate CDMX 2026"
        )
    }

    private static func clean(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              !trimmed.contains("REPLACE_WITH"),
              !trimmed.contains("$(")
        else {
            return nil
        }
        return trimmed
    }
}

private final class GoogleOAuthPresentationProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if canImport(UIKit)
        if Thread.isMainThread {
            return MainActor.assumeIsolated { Self.currentUIKitAnchor() }
        }
        var anchor = ASPresentationAnchor()
        DispatchQueue.main.sync {
            anchor = MainActor.assumeIsolated { Self.currentUIKitAnchor() }
        }
        return anchor
        #elseif canImport(AppKit) && !targetEnvironment(macCatalyst)
        if Thread.isMainThread {
            return Self.currentAppKitAnchor()
        }
        var anchor = ASPresentationAnchor()
        DispatchQueue.main.sync {
            anchor = Self.currentAppKitAnchor()
        }
        return anchor
        #else
        return ASPresentationAnchor()
        #endif
    }

    #if canImport(UIKit)
    @MainActor
    private static func currentUIKitAnchor() -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
            ?? UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first
            ?? ASPresentationAnchor()
    }
    #endif

    #if canImport(AppKit) && !targetEnvironment(macCatalyst)
    private static func currentAppKitAnchor() -> ASPresentationAnchor {
        NSApplication.shared.keyWindow
            ?? NSApplication.shared.windows.first
            ?? ASPresentationAnchor()
    }
    #endif
}

private final class GoogleAuthContinuationBox {
    private var continuation: CheckedContinuation<URL, Error>?

    init(_ continuation: CheckedContinuation<URL, Error>) {
        self.continuation = continuation
    }

    func resume(returning url: URL) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: url)
    }

    func resume(throwing error: Error) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(throwing: error)
    }
}

private struct GoogleOAuthToken: Codable {
    let accessToken: String
    let refreshToken: String?
    let expirationDate: Date
}

private struct GoogleOAuthTokenResponse: Decodable {
    let accessToken: String
    let expiresIn: Int
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
    }
}

private final class GoogleOAuthTokenStore {
    private let key = "jueceo.googleOAuthToken.v1"

    func load() -> GoogleOAuthToken? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(GoogleOAuthToken.self, from: data)
    }

    func save(_ token: GoogleOAuthToken) {
        guard let data = try? JSONEncoder().encode(token) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

private enum GoogleDriveMIME {
    static let driveScope = "https://www.googleapis.com/auth/drive.file"
    static let folder = "application/vnd.google-apps.folder"
    static let pdf = "application/pdf"
}

private struct GoogleDriveMetadata: Encodable {
    let name: String
    let mimeType: String
    let parents: [String]?
}

private struct GoogleDriveFilesResponse: Decodable {
    let files: [GoogleDriveUploadedFile]
}

private struct GoogleDriveErrorResponse: Decodable {
    let error: GoogleDriveError
}

private struct GoogleDriveError: Decodable {
    let message: String
}

private enum GoogleDriveHelpers {
    static func queryEscaped(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
    }

    static func multipartBody(metadata: GoogleDriveMetadata, fileURL: URL, mimeType: String, boundary: String) throws -> Data {
        var body = Data()
        let metadataData = try JSONEncoder().encode(metadata)
        let fileData = try Data(contentsOf: fileURL)

        body.append("--\(boundary)\r\n")
        body.append("Content-Type: application/json; charset=UTF-8\r\n\r\n")
        body.append(metadataData)
        body.append("\r\n--\(boundary)\r\n")
        body.append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n")
        return body
    }
}

private enum GoogleOAuthHelpers {
    static func randomBase64URL(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let result = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if result != errSecSuccess {
            return UUID().uuidString.replacingOccurrences(of: "-", with: "")
        }
        return Data(bytes).base64URLEncodedString()
    }

    static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }

    static func formEncoded(_ values: [String: String]) -> String {
        values
            .map { "\($0.key.formURLEncoded)=\($0.value.formURLEncoded)" }
            .sorted()
            .joined(separator: "&")
    }
}

private extension String {
    var formURLEncoded: String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }

    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
