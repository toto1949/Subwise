import Foundation

nonisolated enum HTTPMethod: String, Sendable { case get = "GET", post = "POST", patch = "PATCH", delete = "DELETE" }

nonisolated struct Endpoint<Response: Decodable & Sendable>: Sendable {
    var path: String
    var method: HTTPMethod = .get
    var body: Data?
    var requiresAuthentication = true
    var idempotencyKey: String?
    var timeoutInterval: TimeInterval = 20
}

nonisolated struct ErrorEnvelope: Decodable { nonisolated struct Detail: Decodable { let code: String; let message: String; let requestId: String }; let error: Detail }
nonisolated enum APIError: LocalizedError {
    case invalidResponse, unauthorized, server(code: String, message: String, requestId: String), transport(Error)
    var errorDescription: String? {
        switch self { case .invalidResponse: "The server returned an invalid response."; case .unauthorized: "Your session expired."; case let .server(_, message, _): message; case let .transport(error): error.localizedDescription }
    }
}

actor APIClient {
    static let shared = APIClient()
    private let session: URLSession
    private let vault: KeychainVault
    private let baseURL: URL
    private let decoder: JSONDecoder
    private var refreshTask: Task<AuthTokens, Error>?

    init(baseURL: URL = AppConfiguration.apiBaseURL, session: URLSession = .shared, vault: KeychainVault = .shared) {
        self.baseURL = baseURL; self.session = session; self.vault = vault
        decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
    }

    func send<Response>(_ endpoint: Endpoint<Response>) async throws -> Response where Response: Decodable & Sendable {
        do {
            return try await perform(endpoint, allowAuthenticationRefresh: true, allowNetworkRetry: endpoint.method == .get)
        } catch let error as APIError { throw error }
        catch { throw APIError.transport(error) }
    }

    func encode<T: Encodable>(_ value: T) throws -> Data { try JSONEncoder.subwise.encode(value) }

    private func perform<Response>(_ endpoint: Endpoint<Response>, allowAuthenticationRefresh: Bool, allowNetworkRetry: Bool) async throws -> Response where Response: Decodable & Sendable {
        var request = URLRequest(url: baseURL.appending(path: endpoint.path))
        request.httpMethod = endpoint.method.rawValue; request.httpBody = endpoint.body; request.timeoutInterval = endpoint.timeoutInterval
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if endpoint.body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let key = endpoint.idempotencyKey { request.setValue(key, forHTTPHeaderField: "Idempotency-Key") }
        if endpoint.requiresAuthentication, let token = try await vault.value(for: "accessToken") { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch where allowNetworkRetry {
            try await Task.sleep(for: .milliseconds(300))
            return try await perform(endpoint, allowAuthenticationRefresh: allowAuthenticationRefresh, allowNetworkRetry: false)
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        if http.statusCode == 401, endpoint.requiresAuthentication, allowAuthenticationRefresh {
            try await refreshSession()
            return try await perform(endpoint, allowAuthenticationRefresh: false, allowNetworkRetry: allowNetworkRetry)
        }
        if http.statusCode == 401 { throw APIError.unauthorized }
        guard 200..<300 ~= http.statusCode else {
            if let envelope = try? decoder.decode(ErrorEnvelope.self, from: data) { throw APIError.server(code: envelope.error.code, message: envelope.error.message, requestId: envelope.error.requestId) }
            throw APIError.invalidResponse
        }
        if Response.self == EmptyResponse.self { return EmptyResponse() as! Response }
        return try decoder.decode(Response.self, from: data)
    }

    private func refreshSession() async throws {
        if let refreshTask {
            _ = try await refreshTask.value
            return
        }
        guard let refreshToken = try await vault.value(for: "refreshToken") else { throw APIError.unauthorized }
        let body = try encode(RefreshRequest(refreshToken: refreshToken))
        let endpoint = Endpoint<AuthTokens>(path: "auth/refresh", method: .post, body: body, requiresAuthentication: false)
        let task = Task<AuthTokens, Error> {
            let tokens = try await self.perform(endpoint, allowAuthenticationRefresh: false, allowNetworkRetry: false)
            try await self.vault.set(tokens.accessToken, for: "accessToken")
            try await self.vault.set(tokens.refreshToken, for: "refreshToken")
            return tokens
        }
        refreshTask = task
        defer { refreshTask = nil }
        _ = try await task.value
    }
}

nonisolated struct EmptyResponse: Decodable, Sendable { init() {} }
nonisolated private struct RefreshRequest: Encodable { let refreshToken: String }
extension JSONEncoder { nonisolated static var subwise: JSONEncoder { let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; return encoder } }

nonisolated enum AppConfiguration {
    static func requestTimeout(for path: String) -> TimeInterval {
        if path.contains("agent/messages") { return 60 }
        return 20
    }
    static var apiBaseURL: URL {
        // Allow SUBWISE_API_BASE_URL override via UserDefaults for on-device debugging without rebuilding
        // e.g. defaults write com.toto.Subwise SUBWISE_API_BASE_URL_OVERRIDE -string "https://subwise-api-.../api/v1"
        if let override = UserDefaults.standard.string(forKey: "SUBWISE_API_BASE_URL_OVERRIDE"), let url = URL(string: override), !override.isEmpty {
            return url
        }
        if let value = Bundle.main.object(forInfoDictionaryKey: "SUBWISE_API_BASE_URL") as? String, let url = URL(string: value), !value.isEmpty {
            #if DEBUG
            #if targetEnvironment(simulator)
            return url
            #else
            if value != "http://127.0.0.1:3000/api/v1" { return url }
            #endif
            #else
            return url
            #endif
        }
        #if DEBUG
        #if targetEnvironment(simulator)
        return URL(string: "http://127.0.0.1:3000/api/v1")!
        #else
        return URL(string: "https://subwise-api-taoufiqmoutaouakil-gmailcoms-projects.vercel.app/api/v1")!
        #endif
        #else
        preconditionFailure("SUBWISE_API_BASE_URL must be configured for production")
        #endif
    }
}
