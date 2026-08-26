import AuthenticationServices
import Foundation
import Observation

nonisolated struct AuthTokens: Codable, Sendable { let accessToken: String; let refreshToken: String; let expiresIn: Int }
nonisolated private struct AppleAuthRequest: Encodable { let identityToken: String; let authorizationCode: String?; let displayName: String? }

@MainActor @Observable
final class AccountSession {
    enum State: Equatable { case checking, signedOut, authenticating, authenticated, development, offline, failed(String) }
    var state: State = .checking
    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let vault: KeychainVault

    init(api: APIClient = .shared, vault: KeychainVault = .shared) {
        self.api = api; self.vault = vault
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-internalDevelopmentMode") { state = .development; return }
        #endif
        Task { state = (try await vault.value(for: "refreshToken")) == nil ? .signedOut : .authenticated }
    }

    func authenticate(credential: ASAuthorizationAppleIDCredential) async {
        state = .authenticating
        guard let tokenData = credential.identityToken, let identityToken = String(data: tokenData, encoding: .utf8) else { state = .failed("Apple did not return a valid identity token."); return }
        let name = [credential.fullName?.givenName, credential.fullName?.familyName].compactMap { $0 }.joined(separator: " ")
        do {
            let authorizationCode = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
            let body = try await api.encode(AppleAuthRequest(identityToken: identityToken, authorizationCode: authorizationCode, displayName: name.isEmpty ? nil : name))
            let tokens = try await api.send(Endpoint<AuthTokens>(path: "auth/apple", method: .post, body: body, requiresAuthentication: false))
            try await vault.set(tokens.accessToken, for: "accessToken"); try await vault.set(tokens.refreshToken, for: "refreshToken")
            state = .authenticated
        } catch { state = .failed(error.localizedDescription) }
    }

    func continueOffline() { state = .offline }
    #if DEBUG
    func continueAsDeveloper() { state = .development }
    #endif
    func signOut() async {
        _ = try? await api.send(Endpoint<EmptyResponse>(path: "auth/logout", method: .post))
        try? await vault.remove("accessToken"); try? await vault.remove("refreshToken"); state = .signedOut
    }
}
